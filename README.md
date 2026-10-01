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
# .env에 SUPABASE_URL, SUPABASE_ANON_KEY,
# GOOGLE_PLACES_API_KEY, NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 입력
flutter run
```

### 장소 검색 키

**국내 (네이버 지역 검색 — 무료 한도 있음)**  
> 개발자센터(`developers.naver.com`) 목록에 **검색이 안 보이는 게 정상**입니다.  
> 2026-07-31부터 검색 API 신규 신청은 **NAVER API HUB**로만 됩니다.

1. [네이버 클라우드 콘솔](https://console.ncloud.com/) 가입/로그인  
2. **Services → Application Services → NAVER API HUB** → 이용 신청  
3. **Application 등록** → API에서 **지역(Local)** 선택  
4. 발급된 Client ID / Secret을 `.env`에 입력  

```env
NAVER_CLIENT_ID=발급값
NAVER_CLIENT_SECRET=발급값
```

**해외 (Google Places)**  
1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트 생성  
2. **Places API (New)** 활성화  
3. API 키를 `.env`의 `GOOGLE_PLACES_API_KEY`에 입력  

키 반영 후 앱을 **완전 재시작** (`flutter run` 다시)하세요.  
키가 없어도 앱은 실행되지만, 해당 지역 검색은 사용할 수 없습니다.

흐름: **장소 추가 → 국내/해외 선택 → 해당 지도 서비스에서 검색·선택 → 저장**.  
「지도에서 보기」는 국내=네이버(좌표), 해외=Google(좌표)로 엽니다.

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
5. 구성원 / 권한 ✅
6. 장소 / 지도 ← **현재**
7. 일정 / Plan B
8. 비용 장부
9. 정산 / 총무
10. 예약 / 사진 / 링크
11. 알림
12. 오프라인 / 동시 수정
13. 완료 / 휴지통 / 백업
14. PDF
15. UI/UX / 테스트
