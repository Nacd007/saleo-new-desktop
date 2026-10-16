/// Native-font receipt lines with the same 1:6:3:3 column proportions.
/// One text command per line avoids positioning and styling every cell.
class ReceiptItemLayout {
  const ReceiptItemLayout(this.charactersPerLine);

  final int charactersPerLine;

  bool numbersFit(String quantity, String unit, String amount) {
    final descriptionStart = (charactersPerLine / 13).round();
    final unitStart = (charactersPerLine * 7 / 13).round();
    final amountStart = (charactersPerLine * 10 / 13).round();
    return quantity.length <= descriptionStart - 1 &&
        unit.length <= amountStart - unitStart - 1 &&
        amount.length <= charactersPerLine - amountStart;
  }

  List<String> lines({
    required String quantity,
    required String description,
    required String unit,
    required String amount,
  }) {
    final descriptionStart = (charactersPerLine / 13).round();
    final unitStart = (charactersPerLine * 7 / 13).round();
    final amountStart = (charactersPerLine * 10 / 13).round();
    final widths = [
      descriptionStart - 1,
      unitStart - descriptionStart - 1,
      amountStart - unitStart - 1,
      charactersPerLine - amountStart,
    ];
    final cells = [quantity, description, unit, amount];
    final wrapped = List.generate(4, (i) => _wrap(cells[i], widths[i]));
    final count = wrapped.fold<int>(
      1,
      (max, cell) => cell.length > max ? cell.length : max,
    );
    return List.generate(count, (line) {
      String cell(int i) => line < wrapped[i].length ? wrapped[i][line] : '';
      return '${cell(0).padRight(descriptionStart)}'
          '${cell(1).padRight(unitStart - descriptionStart)}'
          '${cell(2).padLeft(amountStart - unitStart - 1)} '
          '${cell(3).padLeft(charactersPerLine - amountStart)}';
    });
  }

  List<String> _wrap(String value, int width) {
    var remaining = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final result = <String>[];
    while (remaining.length > width) {
      var end = remaining.lastIndexOf(' ', width);
      if (end < 1) end = width;
      result.add(remaining.substring(0, end));
      remaining = remaining.substring(end).trimLeft();
    }
    result.add(remaining);
    return result;
  }
}
