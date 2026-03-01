import 'package:dio/dio.dart';
void main() async {
  final dio = Dio(BaseOptions(validateStatus: (status) => status != null && status < 300));
  try {
    await dio.post('http://localhost:8001/api/auth/verify-otp', data: {'phone': '+221770000000', 'otp': '000000'});
  } catch (e) {
    print(e.toString());
  }
}
