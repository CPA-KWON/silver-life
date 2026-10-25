import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/facility/welfare_programs.dart';

WelfareProgram _program(String? schedule) =>
    WelfareProgram(facilityName: '상도은빛복지관', title: '요가A', schedule: schedule);

void main() {
  group('WelfareProgram schedule parsing', () {
    test('weekly slots get a weekday and time range', () {
      final p = _program('매주 화요일 13:00~13:50');
      expect(p.weekday, 2);
      expect(p.timeRange, '13:00~13:50');
      expect(p.startMinutes, 13 * 60);
    });

    test('a weekday without 매주 still counts as weekly', () {
      expect(_program('수요일 10:00~13:00').weekday, 3);
    });

    test('monthly, always-open and ranges are not weekly', () {
      expect(_program('매월 첫째 주 화요일 10:00~12:00').weekday, isNull);
      expect(_program('상시').weekday, isNull);
      expect(_program('월~금요일 09:00~18:00').weekday, isNull);
      expect(_program(null).weekday, isNull);
      expect(_program(null).timeRange, isNull);
    });
  });

  group('facilityNameMatches', () {
    test('exact and extra-word NAVER names match', () {
      expect(facilityNameMatches('상도은빛복지관', '상도은빛복지관'), isTrue);
      expect(facilityNameMatches('서울시립 상도은빛복지관', '상도은빛복지관'), isTrue);
      expect(facilityNameMatches('흑석 종합사회복지관', '흑석종합사회복지관'), isTrue);
      expect(facilityNameMatches('상도은빛어르신복지관', '상도은빛복지관'), isTrue);
    });

    test('unrelated or overly generic names do not match', () {
      expect(facilityNameMatches('상도노인종합복지관', '상도은빛복지관'), isFalse);
      expect(facilityNameMatches('복지관', '흑석종합사회복지관'), isFalse);
      expect(facilityNameMatches('', '상도은빛복지관'), isFalse);
    });
  });
}
