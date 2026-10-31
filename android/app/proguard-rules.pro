# 출시 빌드의 코드 줄이기(R8)가 지우면 안 되는 것들.
# WorkManager(광고 라이브러리가 사용)는 Room이 만든 데이터베이스 클래스를 이름으로 찾아
# 만든다. 이 생성자가 지워지면 앱이 시작하자마자 멈춘다.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
