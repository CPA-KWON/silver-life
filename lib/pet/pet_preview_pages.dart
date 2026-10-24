import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'pet_character.dart';
import 'pet_preview_controller.dart';

const _previewText = '화면 미리보기 · 임시 데이터';

Future<T?> _push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '확인',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _notice(BuildContext context, String title, String message) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('확인'),
          ),
        ],
      ),
    );

Widget _title(BuildContext c, String text) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 12),
  child: Text(text, style: Theme.of(c).textTheme.headlineSmall),
);

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color = AppColors.surface});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.title,
    required this.children,
    this.pet,
    this.background = AppColors.background,
  });
  final String title;
  final List<Widget> children;
  final PetPreviewController? pet;
  final Color background;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: background,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      leadingWidth: 80,
      leading: TextButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('이전'),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(_previewText, style: TextStyle(color: AppColors.blueText)),
        const SizedBox(height: 16),
        if (pet != null)
          Align(
            alignment: Alignment.centerRight,
            child: _Panel(
              color: AppColors.rewardTint,
              child: Text('임시 ${pet!.points}P'),
            ),
          ),
        ...children,
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// Entry into the session-only prototype. Existing home data stays independent.
class PetPreviewEntry extends StatelessWidget {
  const PetPreviewEntry({super.key, required this.pet, required this.onTap});
  final PetPreviewController pet;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) => _Panel(
      color: AppColors.blueTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('나의 반려동물 · 미리보기', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Image.asset(
                'assets/pet/${pet.assetStage}/angle.png',
                width: 96,
                height: 96,
                semanticLabel: pet.name ?? '입양을 기다리는 콩이',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pet.adopted
                      ? '${pet.name}와 오늘도 함께해요\n${pet.stageName} · 임시 ${pet.points}P'
                      : '동네 활동과 함께 자라는\n나만의 작은 친구',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onTap,
            child: Text(pet.adopted ? '반려동물 만나기' : '콩이 만나러 가기'),
          ),
        ],
      ),
    ),
  );
}

class PetAdoptionPage extends StatefulWidget {
  const PetAdoptionPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetAdoptionPage> createState() => _PetAdoptionPageState();
}

class _PetAdoptionPageState extends State<PetAdoptionPage> {
  final name = TextEditingController(text: '콩이');
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PreviewPage(
    title: '처음 만나는 우리',
    children: [
      _title(context, '작은 친구의 이름을 지어주세요'),
      const Text('지금은 강아지 한 마리와 시작해요. 함께 활동하며 세 가지 모습으로 자라요.'),
      PetCharacter(pet: widget.pet, height: 220, interactive: false),
      Form(
        key: form,
        child: TextFormField(
          controller: name,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '반려동물 이름'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? '이름을 입력해주세요.' : null,
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final text in ['콩이', '두부', '보리'])
            TextButton(
              onPressed: () => setState(() => name.text = text),
              child: Text(text),
            ),
        ],
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          widget.pet.adopt(name.text);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PetHomePage(pet: widget.pet),
            ),
          );
        },
        child: const Text('함께 시작하기'),
      ),
      const SizedBox(height: 12),
      const Text('입양과 이름은 이번 미리보기에서만 유지돼요. 앱을 다시 시작하면 초기화돼요.'),
    ],
  );
}

class PetHomePage extends StatefulWidget {
  const PetHomePage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetHomePage> createState() => _PetHomePageState();
}

class _PetHomePageState extends State<PetHomePage> {
  Timer? timer;
  String? motion;
  @override
  void initState() {
    super.initState();
    play('hello');
  }

  void play(String next) {
    timer?.cancel();
    motion = next;
    timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => motion = null);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> feed() async {
    final special = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(c, '무엇을 먹여볼까요?'),
            const Text('하루 첫 돌봄은 +5 경험치. 추가 간식은 배부름만 채워줘요.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.pet.fed ? null : () => Navigator.pop(c, false),
              child: Text(widget.pet.fed ? '기본 사료 · 오늘 먹었어요' : '기본 사료 · 무료'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('특별 간식 · 임시 3P'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
    if (special == null || !mounted) return;
    if (special &&
        !await _confirm(
          context,
          '간식을 줄까요?',
          '임시 3P를 사용해요. 실제 포인트는 차감되지 않아요.',
          action: '간식 주기',
        )) {
      return;
    }
    if (!mounted) return;
    try {
      widget.pet.feed(special: special);
      setState(() => play('eat'));
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('맛있게 먹었어요'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PetCharacter(
                  pet: widget.pet,
                  motion: 'eat',
                  height: 170,
                  interactive: false,
                ),
                const Text('배부름이 채워졌어요. 오늘 첫 돌봄이라면 임시 경험치 5를 얻어요.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      await _notice(context, '포인트가 부족해요', '${e.message}\n임시 포인트만 사용해요.');
    }
  }

  Future<void> stages() async {
    final stage = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(c, '성장 단계 미리보기'),
            const Text('세 가지 외형을 바로 확인해요. 임시 경험치를 선택한 단계로 바꿔요.'),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(c, i),
                  child: Text(
                    ['아기 · 0 경험치', '성장기 · 150 경험치', '성체 · 600 경험치'][i],
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
    if (stage == null || !mounted) return;
    widget.pet.previewStage(stage);
    await _push(context, PetGrowthPage(pet: widget.pet));
  }

  Future<void> angles() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _title(c, '다른 각도에서 만나요'),
          const Text('손가락으로 자유롭게 돌려보세요. 앞·옆·뒤 버튼으로 원하는 방향을 바로 볼 수도 있어요.'),
          PetCharacter(pet: widget.pet),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('닫기'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pet,
    builder: (c, _) {
      final pet = widget.pet;
      final actions = <(IconData, String, VoidCallback)>[
        (Icons.ramen_dining_outlined, '먹이 주기', feed),
        (Icons.directions_walk, '산책하기', () => _push(c, PetWalkPage(pet: pet))),
        (Icons.checkroom, '옷 입히기', () => _push(c, PetWardrobePage(pet: pet))),
        (Icons.bar_chart, '성장 기록', () => _push(c, PetRecordsPage(pet: pet))),
      ];
      return _PreviewPage(
        title: '${pet.name}의 집',
        background: AppColors.blueTint,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                '${pet.stageName} ${pet.name}',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              Text(
                '임시 ${pet.points}P',
                style: const TextStyle(
                  color: AppColors.blueText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '오늘도 만나서 반가워요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mintText),
          ),
          LayoutBuilder(
            builder: (c, box) {
              if (box.maxWidth < 330 ||
                  MediaQuery.textScalerOf(c).scale(1) > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PetCharacter(
                      pet: pet,
                      motion: motion,
                      height: 210,
                      interactive: true,
                      showControls: false,
                    ),
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: action.$3,
                          icon: Icon(action.$1),
                          label: Text(action.$2),
                        ),
                      ),
                  ],
                );
              }
              return SizedBox(
                height: 270,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 270,
                      child: PetCharacter(
                        pet: pet,
                        motion: motion,
                        height: 270,
                        interactive: true,
                        showControls: false,
                      ),
                    ),
                    for (var i = 0; i < actions.length; i++)
                      Align(
                        alignment: [
                          const Alignment(-1, -.75),
                          const Alignment(1, -.75),
                          const Alignment(-1, .85),
                          const Alignment(1, .85),
                        ][i],
                        child: SizedBox(
                          width: 98,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.blueText,
                              minimumSize: const Size(0, 80),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            onPressed: actions[i].$3,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(actions[i].$1, size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  actions[i].$2,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          TextButton.icon(
            onPressed: angles,
            icon: const Icon(Icons.rotate_right),
            label: const Text('3D로 돌려보기'),
          ),
          const SizedBox(height: 8),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '성장 · ${pet.experience}${pet.stage == 2 ? " 경험치" : " / ${pet.nextExperience} 경험치"}',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: pet.progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Text('배부름 · ${pet.fullness}/5'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: pet.fullness / 5,
                  minHeight: 8,
                  color: AppColors.rewardText,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _push(c, PetTodayPage(pet: pet)),
            child: const Text('오늘의 활동 · 포인트 모으기'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: stages, child: const Text('세 가지 성장 모습 미리보기')),
          const Text('돌봄과 보상은 앱을 종료하면 초기화돼요. 실제 포인트와 활동은 바뀌지 않아요.'),
        ],
      );
    },
  );
}

class PetWardrobePage extends StatefulWidget {
  const PetWardrobePage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetWardrobePage> createState() => _PetWardrobePageState();
}

class _PetWardrobePageState extends State<PetWardrobePage> {
  String selected = 'hat';
  bool showSelected = true;
  Future<void> apply() async {
    final pet = widget.pet;
    final id = selected;
    final name = PetPreviewController.itemNames[id]!;
    if (!pet.owned.contains(id)) {
      if (!await _confirm(
        context,
        '$name를 살까요?',
        '임시 ${PetPreviewController.itemPrices[id]}P를 사용해요.\n꾸미기는 성장 경험치를 올리지 않아요.',
        action: '구매하고 입히기',
      )) {
        return;
      }
      if (!mounted) return;
      try {
        pet.purchase(id);
      } on StateError catch (e) {
        await _notice(
          context,
          '포인트가 부족해요',
          '${e.message}\n옷을 사거나 실제 포인트를 차감하지 않았어요.',
        );
        return;
      }
    }
    pet.wear(id, remove: !showSelected);
    if (mounted) {
      await _notice(
        context,
        '꾸미기 완료',
        showSelected ? '$name를 입었어요.' : '$name를 벗었어요.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pet,
    builder: (c, _) {
      final pet = widget.pet;
      final outfit = Set<String>.of(pet.worn);
      showSelected ? outfit.add(selected) : outfit.remove(selected);
      final changed =
          outfit.length != pet.worn.length || !outfit.containsAll(pet.worn);
      return _PreviewPage(
        title: '옷 입히기',
        pet: pet,
        children: [
          _Panel(
            color: AppColors.rewardFaintTint,
            child: Column(
              children: [
                Text(changed ? '입혀보기 · 아직 적용되지 않았어요' : '지금 입고 있는 모습이에요'),
                PetCharacter(pet: pet, outfit: outfit, height: 250),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in PetPreviewController.itemNames.keys)
                ChoiceChip(
                  label: Text(
                    {'hat': '모자', 'knit': '옷', 'flower': '액세서리'}[id]!,
                  ),
                  selected: selected == id,
                  onSelected: (_) => setState(() {
                    selected = id;
                    showSelected = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/pet/items/$selected.png',
                  height: 80,
                  semanticLabel: PetPreviewController.itemNames[selected],
                ),
                _title(c, PetPreviewController.itemNames[selected]!),
                Text(
                  pet.worn.contains(selected)
                      ? '착용 중'
                      : pet.owned.contains(selected)
                      ? '보유 중'
                      : '임시 ${PetPreviewController.itemPrices[selected]}P',
                ),
                if (pet.owned.contains(selected))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('입혀서 보기'),
                    value: showSelected,
                    onChanged: (v) => setState(() => showSelected = v!),
                  ),
              ],
            ),
          ),
          FilledButton(
            onPressed: apply,
            child: Text(pet.owned.contains(selected) ? '꾸미기 적용' : '구매하고 입히기'),
          ),
          const SizedBox(height: 12),
          const Text('그냥 돌아가면 입혀보기는 취소돼요. 구매·착용은 이번 미리보기에서만 유지돼요.'),
        ],
      );
    },
  );
}

class PetWalkPage extends StatefulWidget {
  const PetWalkPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetWalkPage> createState() => _PetWalkPageState();
}

class _PetWalkPageState extends State<PetWalkPage> {
  int goal = 0, progress = 0;
  bool started = false, complete = false;
  @override
  Widget build(BuildContext context) => _PreviewPage(
    title: '함께 산책해요',
    children: [
      _title(
        context,
        complete
            ? '산책 완료 모습을 확인했어요'
            : started
            ? '한 걸음씩 함께 가요'
            : '오늘은 어떻게 걸어볼까요?',
      ),
      const Text('산책 화면 시연이에요. 실제 걸음 수와 위치는 측정하지 않아요.'),
      PetCharacter(
        pet: widget.pet,
        height: 210,
        interactive: false,
        motion: started && !complete ? 'walk' : null,
      ),
      if (!started) ...[
        RadioGroup<int>(
          groupValue: goal,
          onChanged: (v) => setState(() => goal = v!),
          child: Column(
            children: const [
              RadioListTile<int>(title: Text('1,000걸음 걷기'), value: 0),
              RadioListTile<int>(
                title: Text('가까운 시설 도착하기'),
                subtitle: Text('100m 이내 · 2분 머무르기'),
                value: 1,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => setState(() => started = true),
          child: const Text('산책 화면 시작하기'),
        ),
      ] else ...[
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                goal == 0
                    ? '임시 ${progress * 500} / 1,000걸음'
                    : ['시설로 이동 중', '100m 안에 도착했어요', '2분 머무르기 완료'][progress],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress / 2, minHeight: 12),
              const SizedBox(height: 12),
              Text(
                widget.pet.walked ? '오늘의 임시 보상을 받았어요' : '첫 완료 시 임시 2P · 10 경험치',
              ),
            ],
          ),
        ),
        if (!complete && progress < 2)
          FilledButton(
            onPressed: () =>
                setState(() => progress = (progress + 1).clamp(0, 2)),
            child: Text(progress < 2 ? '진행 상황 미리보기' : '목표 도달 상태'),
          ),
        if (progress == 2 && !complete) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              widget.pet.walk();
              setState(() => complete = true);
            },
            child: const Text('완료 · 임시 보상 받기'),
          ),
        ],
        if (complete)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('반려동물에게 돌아가기'),
          ),
        TextButton(
          onPressed: () async {
            if (complete ||
                await _confirm(
                  context,
                  '산책 미리보기를 그만할까요?',
                  '중단하면 임시 보상은 지급되지 않아요.',
                  action: '그만하기',
                )) {
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('산책 미리보기 나가기'),
        ),
      ],
    ],
  );
}

class PetTodayPage extends StatelessWidget {
  const PetTodayPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) => _PreviewPage(
      title: '오늘의 활동',
      pet: pet,
      children: [
        _title(c, '오늘도 콩이와 한 걸음'),
        const Text('아래 출석·미션·프로그램·광고는 임시 상황이에요. 기존 앱의 실제 신청·출석과 연결되지 않아요.'),
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(c, '출석과 주간 미션'),
              Text(
                pet.attended ? '오늘 출석 완료 · 임시 보상 지급됨' : '출석하면 임시 1P · 5 경험치',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: pet.attended
                    ? null
                    : () async {
                        pet.attendance();
                        await _notice(
                          c,
                          '오늘도 반가워요',
                          '임시 1P와 5 경험치를 받았어요.\n실제 출석 도장은 찍히지 않아요.',
                        );
                      },
                child: Text(pet.attended ? '출석 확인 완료' : '출석 보상 미리보기'),
              ),
              const SizedBox(height: 16),
              const Text('주간 미션 연결 예시\n1. 익숙한 동네\n2. 새로운 장소\n3. 함께하는 활동'),
              const SizedBox(height: 12),
              const Text(
                '실제 미션의 세 단계는 유지해요. 참여 보상은 프로그램 완료와 중복 지급하지 않는 방향이에요.',
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(c, '기관 프로그램 참여'),
              const Text('탐색 → 신청 → 기관 승인 → 참여 완료\n신청만으로는 보상을 주지 않아요.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _push(c, PetProgramPreviewPage(pet: pet)),
                child: const Text('신청부터 보상까지 살펴보기'),
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(c, '선택형 광고'),
              Text('임시 1P · 하루 최대 2회\n현재 ${pet.ads}/2회 · 성장 경험치는 없어요'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: pet.ads >= 2
                    ? null
                    : () async {
                        if (!await _confirm(
                          c,
                          '광고 보상 화면을 볼까요?',
                          '실제 광고를 재생하지 않아요. 완료 버튼으로 보상 상황만 확인해요.',
                          action: '완료 상황 보기',
                        )) {
                          return;
                        }
                        pet.advert();
                        if (c.mounted) {
                          await _notice(
                            c,
                            '임시 1P를 받았어요',
                            '실제 광고 수익과 포인트는 발생하지 않았어요.',
                          );
                        }
                      },
                child: Text(pet.ads >= 2 ? '오늘의 임시 보상 완료' : '광고 보상 미리보기'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PetProgramPreviewPage extends StatefulWidget {
  const PetProgramPreviewPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetProgramPreviewPage> createState() => _PetProgramPreviewPageState();
}

class _PetProgramPreviewPageState extends State<PetProgramPreviewPage> {
  late int step = widget.pet.programCompleted ? 3 : 0;
  @override
  Widget build(BuildContext context) => _PreviewPage(
    title: '프로그램 연계 예시',
    children: [
      _title(context, '우리 동네 가벼운 체조'),
      const Text('가상의 프로그램이에요. 실제 기관이나 모집 정보가 아니에요.'),
      const SizedBox(height: 24),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              context,
              ['프로그램 상세', '신청 · 승인 대기', '기관 승인 · 참여 예정', '기관 참여 완료 확인'][step],
            ),
            Text(
              [
                '지역 시설의 활동을 살펴보고 신청해요.',
                '기관 담당자가 신청을 확인해요. 아직 보상은 없어요.',
                '활동에 실제로 참여한 뒤 기관이 완료를 확인해요.',
                '임시 보상 5P와 30 경험치를 한 번만 받아요.',
              ][step],
            ),
          ],
        ),
      ),
      FilledButton(
        onPressed: () {
          if (step < 3) {
            setState(() => step++);
          } else {
            final already = widget.pet.programCompleted;
            widget.pet.completeProgram();
            _notice(
              context,
              already ? '이미 보상을 받았어요' : '활동과 함께 성장했어요',
              already
                  ? '같은 완료 건은 중복 지급하지 않아요.'
                  : '임시 5P · 30 경험치를 받았어요. 실제 기관 신청은 생성되지 않았어요.',
            );
          }
        },
        child: Text(
          ['신청 상황 보기', '기관 승인 상황 보기', '참여 완료 상황 보기', '임시 참여 보상 받기'][step],
        ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('오늘의 활동으로 돌아가기'),
      ),
    ],
  );
}

class PetGrowthPage extends StatelessWidget {
  const PetGrowthPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext context) => _PreviewPage(
    title: '성장 모습 미리보기',
    children: [
      _title(context, '${pet.name}의 ${pet.stageName} 모습이에요'),
      PetCharacter(pet: pet, height: 300),
      const Text('아기 → 성장기 → 성체\n돌봄과 동네 활동의 경험치로 자라요. 옷을 사도 성장은 빨라지지 않아요.'),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('이 모습으로 돌아가기'),
      ),
    ],
  );
}

class PetRecordsPage extends StatelessWidget {
  const PetRecordsPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) => _PreviewPage(
      title: '함께한 기록',
      children: [
        _title(c, '${pet.name}와 만든 이야기'),
        _Panel(
          child: Text(
            '${pet.stageName} · ${pet.experience} 경험치\n꾸미기 아이템 ${pet.owned.length}개\n미리보기 기록 ${pet.records.length}개',
          ),
        ),
        if (pet.records.isEmpty)
          const _Panel(child: Text('아직 함께한 기록이 없어요. 먹이를 주거나 활동 화면을 눌러보세요.')),
        OutlinedButton(
          onPressed: () => _push(c, const PetDialogsPreviewPage()),
          child: const Text('공통 안내 화면 보기'),
        ),
        const SizedBox(height: 16),
        for (final record in pet.records) _Panel(child: Text(record)),
        OutlinedButton(
          onPressed: () async {
            if (!await _confirm(
              c,
              '미리보기를 처음부터 볼까요?',
              '임시 이름·포인트·꾸미기 기록을 모두 초기화해요. 실제 회원정보는 바뀌지 않아요.',
              action: '초기화',
            )) {
              return;
            }
            pet.reset();
            if (c.mounted) Navigator.of(c).popUntil((route) => route.isFirst);
          },
          child: const Text('미리보기 초기화'),
        ),
      ],
    ),
  );
}

/// Explicit gallery for states that cannot occur without a real backend/SDK.
class PetDialogsPreviewPage extends StatelessWidget {
  const PetDialogsPreviewPage({super.key});
  static const examples = <(String, String)>[
    ('구매 확인', '털모자를 살까요? 임시 10P를 사용해요.'),
    ('포인트 부족', '포인트가 부족해요. 오늘의 활동에서 모아보세요.'),
    ('구매 완료', '아이템을 샀어요. 옷장에서 입혀볼 수 있어요.'),
    ('착용 완료', '새 옷이 잘 어울려요. 반려동물 홈에서도 볼 수 있어요.'),
    ('먹이 주기 완료', '맛있게 먹었어요. 배부름과 첫 돌봄 경험치가 채워졌어요.'),
    ('보상 획득', '활동과 함께 성장했어요. 임시 포인트와 경험치를 받았어요.'),
    ('이미 받은 보상', '이미 받은 보상이에요. 같은 활동의 보상은 한 번만 받아요.'),
    ('처리 중', '잠시만 기다려주세요. 처리 중 화면의 모양만 확인하는 예시예요.'),
    ('오류 · 다시 시도', '처리하지 못했어요. 포인트는 차감되지 않았어요. 잠시 후 다시 시도해주세요.'),
    ('광고 준비 중', '광고를 준비하고 있어요. 잠시 후 다시 확인해주세요.'),
    ('광고 시청 미완료', '광고를 끝까지 보지 않아 보상을 받지 못했어요.'),
    ('일일 횟수 소진', '오늘 받을 수 있는 광고 보상을 모두 받았어요. 내일 다시 만나요.'),
  ];
  @override
  Widget build(BuildContext context) => _PreviewPage(
    title: '공통 안내 미리보기',
    children: [
      const Text('실제 오류나 광고 상태가 아니에요. 아래 버튼으로 안내창 모양만 확인해요.'),
      const SizedBox(height: 20),
      for (final example in examples)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
            onPressed: () => _notice(context, example.$1, example.$2),
            child: Text(example.$1),
          ),
        ),
    ],
  );
}
