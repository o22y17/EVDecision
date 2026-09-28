import unittest
from unittest.mock import Mock, patch
import requests
import app


class CatalogueTests(unittest.TestCase):
    def setUp(self):
        app._cache.clear()
        self.client = app.app.test_client()

    def test_cache_preserves_original_fetch_time(self):
        response = Mock(status_code=200)
        response.json.return_value = {"data": [{"sarjIstasyonuNo": "1"}]}
        with patch.object(app.requests, "request", return_value=response) as request:
            with patch.object(app.time, "time", return_value=1000):
                first = self.client.get('/stations?brands=TESLA').get_json()
            with patch.object(app.time, "time", return_value=1100):
                cached = self.client.get('/stations?brands=TESLA').get_json()
        self.assertEqual(request.call_count, 1)
        self.assertEqual(first['fetchedAt'], cached['fetchedAt'])
        self.assertEqual(cached['servedAt'], 1100)
        self.assertIsNone(cached['sourceUpdatedAt'])
        self.assertEqual(cached['availability'], 'unknown')

    def test_timeout_preserves_other_brand_results(self):
        response = Mock(status_code=200)
        response.json.return_value = {"data": [{"sarjIstasyonuNo": "1"}]}
        with patch.object(app.requests, "request", side_effect=[requests.Timeout(), response]):
            result = self.client.get('/stations?brands=TESLA,ZES')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(len(result.get_json()['stations']), 1)
        self.assertEqual(len(result.get_json()['partialFailures']), 1)

    def test_invalid_payload_is_not_cached(self):
        response = Mock(status_code=200)
        response.json.return_value = {"data": None}
        with patch.object(app.requests, "request", return_value=response):
            result = self.client.get('/stations?brands=TESLA').get_json()
        self.assertTrue(result['partialFailures'])
        self.assertIsNone(result['fetchedAt'])
        self.assertFalse(app._cache)

    def test_unsupported_or_excess_brands_are_not_silently_dropped(self):
        with patch.object(app.requests, "request") as request:
            for brands in ['TESLA,UNKNOWN', 'TESLA,ZES,TRUGO,ESARJ', '']:
                self.assertEqual(self.client.get('/stations?brands=' + brands).status_code, 400)
        request.assert_not_called()

    def test_expired_cache_fetches_new_catalogue(self):
        app._cache['TESLA'] = {'timestamp': 1, 'records': [{'old': True}]}
        response = Mock(status_code=200)
        response.json.return_value = {'data': [{'new': True}]}
        with patch.object(app.time, 'time', return_value=app.CACHE_TTL_SECONDS + 2):
            with patch.object(app.requests, 'request', return_value=response) as request:
                result = self.client.get('/stations?brands=TESLA').get_json()
        request.assert_called_once()
        self.assertEqual(result['stations'], [{'new': True}])
        self.assertEqual(result['cachedBrands'], [])


if __name__ == '__main__':
    unittest.main()
