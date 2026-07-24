import unittest

from starlette.routing import Match

from routers.deliveries import router


class DriverPresenceRouteTests(unittest.TestCase):
    def test_presence_endpoint_is_not_captured_as_a_mission_id(self):
        scope = {
            "type": "http",
            "path": "/driver-presence/location",
            "root_path": "",
            "method": "PUT",
        }

        matched_paths = [
            route.path
            for route in router.routes
            if route.matches(scope)[0] == Match.FULL
        ]

        self.assertGreater(len(matched_paths), 0)
        self.assertEqual(matched_paths[0], "/driver-presence/location")


if __name__ == "__main__":
    unittest.main()
