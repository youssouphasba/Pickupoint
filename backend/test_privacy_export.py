import unittest

from routers.privacy import _pdf_value, _user_parcel_query


class PrivacyExportTests(unittest.TestCase):
    def test_parcel_query_does_not_match_missing_phone(self):
        query = _user_parcel_query({"user_id": "user-1", "phone": None})
        self.assertEqual(
            query,
            {
                "$or": [
                    {"sender_user_id": "user-1"},
                    {"recipient_user_id": "user-1"},
                ]
            },
        )

    def test_parcel_query_includes_a_real_phone(self):
        query = _user_parcel_query(
            {"user_id": "user-1", "phone": "+221770000000"}
        )
        self.assertIn({"recipient_phone": "+221770000000"}, query["$or"])

    def test_pdf_values_escape_reportlab_markup(self):
        self.assertEqual(_pdf_value("A&B <test>"), "A&amp;B &lt;test&gt;")


if __name__ == "__main__":
    unittest.main()
