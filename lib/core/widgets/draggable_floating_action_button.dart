import 'package:flutter/material.dart';
import 'package:myexpence/core/theme/app_theme.dart';

class DraggableFloatingActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double initialBottom;
  final double initialRight;

  const DraggableFloatingActionButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.add,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.initialBottom = 24,
    this.initialRight = 16,
  });

  @override
  State<DraggableFloatingActionButton> createState() => _DraggableFloatingActionButtonState();
}

class _DraggableFloatingActionButtonState extends State<DraggableFloatingActionButton> {
  Offset _offset = Offset.zero;
  bool _isDragging = false;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    const fabSize = 56.0;

    return Positioned(
      right: widget.initialRight,
      bottom: widget.initialBottom,
      child: Transform.translate(
        offset: _offset,
        child: GestureDetector(
          onPanStart: (_) {
            _dragDistance = 0;
            setState(() {
              _isDragging = true;
            });
          },
          onPanUpdate: (details) {
            _dragDistance += details.delta.distance;
            setState(() {
              _offset += details.delta;
            });
          },
          onPanEnd: (_) {
            setState(() {
              _isDragging = false;
            });
            if (_dragDistance < 10) {
              widget.onPressed();
            }
          },
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _isDragging ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Material(
              elevation: _isDragging ? 12.0 : 6.0,
              shape: const CircleBorder(),
              color: widget.backgroundColor ?? AppTheme.primaryColor,
              shadowColor: Colors.black45,
              child: SizedBox(
                width: fabSize,
                height: fabSize,
                child: Center(
                  child: Icon(
                    widget.icon,
                    color: widget.foregroundColor ?? Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating Draggable & Moveable Save Button that can be placed anywhere on screen
class DraggableSaveButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final bool isSubmitting;
  final double initialBottom;
  final double initialRight;

  const DraggableSaveButton({
    super.key,
    required this.onPressed,
    this.label = 'Save',
    this.icon = Icons.check_circle_outline,
    this.isSubmitting = false,
    this.initialBottom = 24,
    this.initialRight = 16,
  });

  @override
  State<DraggableSaveButton> createState() => _DraggableSaveButtonState();
}

class _DraggableSaveButtonState extends State<DraggableSaveButton> {
  Offset _offset = Offset.zero;
  bool _isDragging = false;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    const buttonHeight = 52.0;

    return Positioned(
      right: widget.initialRight,
      bottom: widget.initialBottom,
      child: Transform.translate(
        offset: _offset,
        child: GestureDetector(
          onPanStart: (_) {
            _dragDistance = 0;
            setState(() {
              _isDragging = true;
            });
          },
          onPanUpdate: (details) {
            _dragDistance += details.delta.distance;
            setState(() {
              _offset += details.delta;
            });
          },
          onPanEnd: (_) {
            setState(() {
              _isDragging = false;
            });
            if (_dragDistance < 10 && !widget.isSubmitting) {
              widget.onPressed();
            }
          },
          onTap: widget.isSubmitting ? null : widget.onPressed,
          child: AnimatedScale(
            scale: _isDragging ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Material(
              elevation: _isDragging ? 12.0 : 8.0,
              borderRadius: BorderRadius.circular(26),
              color: AppTheme.primaryColor,
              shadowColor: Colors.black54,
              child: Container(
                height: buttonHeight,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isSubmitting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    else
                      Icon(widget.icon, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
