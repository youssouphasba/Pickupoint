import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.onCompleted});
  final ValueChanged<String> onCompleted;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final List<TextEditingController> _controllers =
      List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  String? _lastSubmittedCode;

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _notifyIfComplete() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length == 6) {
      if (_lastSubmittedCode != code) {
        _lastSubmittedCode = code;
        widget.onCompleted(code);
      }
      return;
    }
    _lastSubmittedCode = null;
  }

  void _focusNextEmptyField() {
    for (var i = 0; i < _controllers.length; i++) {
      if (_controllers[i].text.isEmpty) {
        _focusNodes[i].requestFocus();
        return;
      }
    }
    FocusScope.of(context).unfocus();
  }

  void _fillFromPaste(String rawValue, int startIndex) {
    final digits = rawValue.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return;
    }

    var cursor = startIndex;
    for (final digit in digits.split('')) {
      if (cursor >= _controllers.length) {
        break;
      }
      _controllers[cursor].text = digit;
      _controllers[cursor].selection = const TextSelection.collapsed(offset: 1);
      cursor++;
    }

    _focusNextEmptyField();
    _notifyIfComplete();
  }

  void _onChanged(String value, int index) {
    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      _controllers[index].clear();
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      _notifyIfComplete();
      return;
    }

    if (digits.length > 1) {
      _fillFromPaste(digits, index);
      return;
    }

    _controllers[index].text = digits;
    _controllers[index].selection = const TextSelection.collapsed(offset: 1);

    if (index < _controllers.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
    _notifyIfComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        6,
        (index) => SizedBox(
          width: 48,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: TextInputType.number,
            textInputAction: index == _controllers.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            autofillHints:
                index == 0 ? const [AutofillHints.oneTimeCode] : null,
            autocorrect: false,
            enableSuggestions: false,
            showCursor: false,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              counterText: "",
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
            onChanged: (v) => _onChanged(v, index),
          ),
        ),
      ),
    );
  }
}
