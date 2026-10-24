import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'pet_preview_controller.dart';
import 'pet_scene.dart';

/// Native mobile uses a real offline GLB; unsupported renderers use labelled PNGs.
class PetCharacter extends StatefulWidget {
  const PetCharacter({
    super.key,
    required this.pet,
    this.height = 270,
    this.motion,
    this.interactive = true,
    this.outfit,
    this.showControls = true,
  });
  final PetPreviewController pet;
  final double height;
  final String? motion;
  final bool interactive;
  final bool showControls;
  final Set<String>? outfit;
  @override
  State<PetCharacter> createState() => _PetCharacterState();
}

class _PetCharacterState extends State<PetCharacter> {
  final _scene = GlobalKey<PetSceneState>();
  bool _entrance = false;
  @override
  void initState() {
    super.initState();
    _entrance = widget.motion == 'hello';
  }

  int angle = 0;
  double drag = 0;
  @override
  Widget build(BuildContext context) {
    final native3d = PetScene.supported;
    final pet = widget.pet;
    final view = ['angle', 'side', 'back', 'front'][angle];
    final motion = widget.motion;
    return Column(
      children: [
        GestureDetector(
          onHorizontalDragUpdate: widget.interactive && !native3d
              ? (d) {
                  drag += d.delta.dx;
                  if (drag.abs() > 45) {
                    setState(() => angle = (angle + (drag > 0 ? 1 : 3)) % 4);
                    drag = 0;
                  }
                }
              : null,
          child: Semantics(
            image: true,
            label:
                '${pet.name ?? '콩이'} ${pet.stageName} ${native3d ? '3D 캐릭터' : ['사선', '옆모습', '뒷모습', '앞모습'][angle]}',
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: native3d
                  ? PetScene(
                      key: _scene,
                      stage: pet.assetStage,
                      outfit: widget.outfit ?? pet.worn,
                      motion: motion,
                      entrance: _entrance,
                      interactive: widget.interactive,
                    )
                  : motion != null &&
                        pet.stage == 0 &&
                        (widget.outfit ?? pet.worn).isEmpty &&
                        !MediaQuery.disableAnimationsOf(context)
                  ? Image.asset(
                      'assets/pet/motion/$motion.gif',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/pet/${pet.assetStage}/$view.png',
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                        for (final id in ['knit', 'hat', 'flower'])
                          if ((widget.outfit ?? pet.worn).contains(id))
                            Image.asset(
                              'assets/pet/${pet.assetStage}/${id}_$view.png',
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                            ),
                      ],
                    ),
            ),
          ),
        ),
        if (widget.interactive && widget.showControls)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              for (var i = 0; i < 4; i++)
                TextButton(
                  onPressed: () {
                    setState(() => angle = i);
                    _scene.currentState?.view(
                      ['angle', 'side', 'back', 'front'][i],
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: angle == i
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  child: Text(['사선', '옆', '뒤', '앞'][i]),
                ),
            ],
          ),
      ],
    );
  }
}
