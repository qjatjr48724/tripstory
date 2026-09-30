# tripstory

여행을 계획하고 → 함께 관리하고 → 여행 중 사용하고 → 비용을 정산하고 → 여행이 끝난 뒤 기록으로 남기는 모바일 앱

기준 문서: [`docs/여행_일정_관리_앱_개발_제안서_최종.md`](docs/여행_일정_관리_앱_개발_제안서_최종.md)

## 기술 스택

| 항목 | 방향 |
|---|---|
| 클라이언트 | Flutter + Dart |
| 상태관리 | Riverpod |
| 라우팅 | go_router |
| 백엔드 | Supabase (Auth / DB / Storage / Realtime) |
| 플랫폼 | Android + iOS |

## 시작하기

```bash
flutter pub get
cp .env.example .env   # Windows: copy .env.example .env
# .env에 SUPABASE_URL, SUPABASE_ANON_KEY 입력 (2단계)
flutter run
```

## 폴더 구조

```text
lib/
  app/           # MaterialApp, 라우터
  core/          # 설정, 상수, 테마
  features/
    auth/        # 인증
    travel/      # 여행
```

## 개발 순서 (제안서 16.2)

1. Flutter 기본 프로젝트 ✅
2. Supabase 연결 및 DB ✅
3. 회원가입 / 로그인 ✅
4. 여행 생성 / 목록 / 초대 ✅
5. 구성원 / 권한 ← **현재**
6. 장소 / 지도
7. 일정 / Plan B
8. 비용 장부
9. 정산 / 총무
10. 예약 / 사진 / 링크
11. 알림
12. 오프라인 / 동시 수정
13. 완료 / 휴지통 / 백업
14. PDF
15. UI/UX / 테스트
