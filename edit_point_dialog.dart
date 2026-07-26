import 'package:flutter/material.dart';
import 'io_point.dart';
import 'storage.dart';

Future<void> showEditPointDialog(BuildContext context, IOPoint point,
    {required VoidCallback onSaved}) async {
  final labelController = TextEditingController(text: point.label);
  final minController =
      TextEditingController(text: point.analogMin.toStringAsFixed(0));
  final maxController =
      TextEditingController(text: point.analogMax.toStringAsFixed(0));
  AnalogMode selectedMode = point.analogMode;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        final isAnalog = point.category == PointCategory.analog;
        return AlertDialog(
          title: Text('Adres ${point.address} — Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'İsim (etiket)',
                    hintText: 'Örn: Sintine Pompası',
                  ),
                ),
                if (isAnalog) ...[
                  const SizedBox(height: 16),
                  const Text('Bu analog sinyal ne için kullanılacak?'),
                  RadioListTile<AnalogMode>(
                    dense: true,
                    title: const Text('Sadece okuma / gösterge'),
                    value: AnalogMode.display,
                    groupValue: selectedMode,
                    onChanged: (v) => setState(() => selectedMode = v!),
                  ),
                  RadioListTile<AnalogMode>(
                    dense: true,
                    title: const Text('Kontrol edilecek (kaydırıcı ile ayar)'),
                    value: AnalogMode.control,
                    groupValue: selectedMode,
                    onChanged: (v) => setState(() => selectedMode = v!),
                  ),
                  if (selectedMode == AnalogMode.control)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Min'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Max'),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                point.label = labelController.text.trim().isEmpty
                    ? point.label
                    : labelController.text.trim();
                point.analogMode = selectedMode;
                point.analogMin =
                    double.tryParse(minController.text) ?? point.analogMin;
                point.analogMax =
                    double.tryParse(maxController.text) ?? point.analogMax;
                await Storage.savePoint(point);
                onSaved();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      });
    },
  );
}
