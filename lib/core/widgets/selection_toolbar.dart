import 'package:flutter/material.dart';

/// Use it as the `contextMenuBuilder` of any [SelectableText].
Widget buildMamaSelectionToolbar(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        label: 'Copy',
        onPressed: () =>
            editableTextState.copySelection(SelectionChangedCause.toolbar),
      ),
      ContextMenuButtonItem(
        label: 'Select all',
        onPressed: () =>
            editableTextState.selectAll(SelectionChangedCause.toolbar),
      ),
      ContextMenuButtonItem(
        label: 'Share',
        onPressed: () => _share(editableTextState),
      ),
    ],
  );
}

Future<void> _share(EditableTextState state) async {
  // Hide first: the native share sheet should not sit on top of the selection
  // toolbar (and the toolbar would otherwise stay visible after returning).
  state.hideToolbar();
  await state.shareSelection(SelectionChangedCause.toolbar);
}
