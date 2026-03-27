import 'package:flutter/material.dart';

class ExampleButton extends StatefulWidget {
  const ExampleButton({super.key});

  @override
  State<ExampleButton> createState() => _ExampleButtonState();
}

class _ExampleButtonState extends State<ExampleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _pressed = !_pressed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 120,
        height: 48,
        decoration: BoxDecoration(
          color: _pressed ? Colors.green : Colors.blue,
          borderRadius: BorderRadius.circular(_pressed ? 24 : 8),
        ),
        alignment: Alignment.center,
        child: Text(
          _pressed ? 'Done' : 'Press me',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
