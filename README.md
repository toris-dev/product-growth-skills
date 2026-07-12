# Product Growth Skills

> Open-source agent skills for app-store growth, web SEO/GEO, Flutter and Expo Android performance, and interactive 2D/3D product design.

웹 검색 노출부터 앱 스토어 전환, Flutter·Expo 성능 및 인터랙티브 디자인까지 제품 성장에 자주 필요한 작업을 재사용 가능한 6개 에이전트 스킬로 제공합니다.

각 스킬은 단순 체크리스트가 아니라 다음 흐름을 따릅니다.

```text
상황 확인 → 근거 수집 → 작업 범위 선택 → 제작/구현 → 검증 → 한계와 결과 전달
```

## 스킬 목록

| 스킬 | 주요 기능 | 사용 시점 |
|---|---|---|
| [`app-store-listing-creator`](app-store-listing-creator/) | Play Store·App Store 아이콘 방향, 이미지 생성 프롬프트, 스크린샷 스토리보드, 짧은/상세 설명, 키워드와 현지화 | 신규 출시, 리브랜딩, 스토어 전환 개선, 등록 자료 제작 |
| [`seo-geo-optimizer`](seo-geo-optimizer/) | 기술 SEO, 검색 의도/키워드 맵, 구조화 데이터, 내부 링크, GEO, `llms.txt` | 웹사이트 출시·이전·감사, 검색/AI 답변 노출 구조 개선 |
| [`flutter-android-performance`](flutter-android-performance/) | 시작 속도, 프레임/jank, CPU, 메모리, 네트워크, 에셋·앱 크기 측정과 최적화 | Flutter Android 성능 저하, 회귀, 출시 전 성능 점검 |
| [`flutter-interactive-design`](flutter-interactive-design/) | Flutter UI 방향, 반응형 컴포넌트, 제스처, 2D 모션, 셰이더·제한된 3D, 접근성/성능 폴백 | 화면·온보딩·시각화·게임형 경험 설계와 구현 |
| [`expo-android-performance`](expo-android-performance/) | Expo의 JS/UI/native 경계, 시작·렌더링·리스트·메모리·번들/앱 크기 최적화 | Expo Android 성능 문제, prebuild 소유권을 고려한 개선 |
| [`expo-interactive-design`](expo-interactive-design/) | Expo 네이티브 UI, 라우팅·제스처, 2D canvas/모션, 제한된 3D, Android 검증 | Expo 화면·전환·시각화·몰입형 상호작용 설계와 구현 |

## 설치

각 폴더는 독립적인 스킬입니다. Codex가 사용하는 스킬 디렉터리에 저장소 전체 또는 필요한 폴더만 복사하거나 심볼릭 링크로 연결할 수 있습니다. 기본 `CODEX_HOME`을 사용하는 경우 일반적인 위치는 `~/.codex/skills`입니다.

### 저장소 전체 연결

```bash
git clone https://github.com/toris-dev/product-growth-skills.git
mkdir -p ~/.codex/skills
for skill in app-store-listing-creator seo-geo-optimizer flutter-android-performance flutter-interactive-design expo-android-performance expo-interactive-design; do
  ln -s "$(pwd)/product-growth-skills/$skill" "$HOME/.codex/skills/$skill"
done
```

이미 같은 이름의 폴더나 링크가 있으면 덮어쓰기 전에 내용을 확인하세요. 별도의 `CODEX_HOME`을 사용한다면 해당 환경의 `skills` 디렉터리로 경로를 바꾸면 됩니다.

### 한 개만 복사

```bash
mkdir -p ~/.codex/skills
cp -R product-growth-skills/seo-geo-optimizer ~/.codex/skills/
cp -R product-growth-skills/shared-references ~/.codex/skills/
```

공통 근거 규칙을 사용하는 스킬은 저장소의 `shared-references/`를 상대 경로로 참조합니다. 단일 스킬을 복사할 때도 위 예시처럼 해당 공통 폴더를 같은 부모 디렉터리에 배치하세요. 가장 안전한 방식은 저장소 전체를 clone한 뒤 필요한 스킬 폴더를 링크하는 것입니다.

설치 후 새 Codex 작업에서 `$skill-name`을 명시적으로 호출하세요. 사용 중인 에이전트가 `SKILL.md` 규격을 지원하더라도 설치 위치와 자동 호출 방식은 제품마다 다를 수 있습니다.

## 사용 예시

```text
Use $app-store-listing-creator to inspect my app and create Korean and English
Play Store/App Store icon directions, screenshot storyboards, and final copy.

Use $seo-geo-optimizer to audit this website, map search intent and keywords,
improve GEO-ready content, and create an evidence-based llms.txt if appropriate.

Use $flutter-android-performance to reproduce this Android scroll jank,
measure a profile/release baseline, implement the proven fix, and compare results.

Use $flutter-interactive-design to redesign this Flutter onboarding with a
distinct visual direction, gesture-driven 2D motion, and an accessible 3D moment.

Use $expo-android-performance to diagnose slow Android startup in this Expo app
without editing native files that prebuild owns, then verify a production build.

Use $expo-interactive-design to create an Expo product viewer with intentional
native UI, interactive motion, a bounded 3D scene, and low-end/reduced-motion fallbacks.
```

한국어로 요청하면 산출물도 한국어로 작성하도록 각 스킬에 명시되어 있습니다.

## 저장소 구조

```text
product-growth-skills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── scripts/validate_skills.py
├── shared-references/evidence-and-verification.md
├── app-store-listing-creator/
├── seo-geo-optimizer/
├── flutter-android-performance/
├── flutter-interactive-design/
├── expo-android-performance/
└── expo-interactive-design/
```

각 스킬에는 다음 파일이 포함됩니다.

- `SKILL.md`: 호출 조건, 작업 흐름, 변경 권한, 검증 기준
- `agents/openai.yaml`: 표시 이름과 시작 프롬프트
- `references/`: 해당 작업에서 필요할 때만 읽는 상세 산출물·판단 기준

## 설계 원칙과 한계

- 바뀔 수 있는 스토어 규격, 검색엔진 정책, 프레임워크 API는 작업 시점의 공식 문서를 확인합니다.
- 감사·진단 요청은 외부 게시나 코드 변경 권한을 뜻하지 않습니다.
- 스토어 승인, 검색 순위, AI 답변 인용, 성능 향상을 보장하지 않습니다.
- 이미지 생성 기능이 있으면 사용자의 요청과 권한에 따라 실제 시안을 만들고, 없으면 제작 가능한 브리프와 프롬프트를 제공합니다.
- 성능 스킬은 비교 가능한 전후 측정 없이 “최적화 완료”라고 판단하지 않습니다.
- 디자인 스킬은 reduced motion, 보조 기술, 저사양 기기, 로딩/오류 상태를 핵심 산출물로 취급합니다.
- 외부 서비스, 스토어 콘솔, 분석 도구, 실제 기기 접근이 없으면 해당 부분은 검증되지 않은 한계로 보고됩니다.

## 검증

저장소 구조와 메타데이터를 검사합니다.

```bash
python3 scripts/validate_skills.py
```

공식 `skill-creator` 도구가 설치된 환경에서는 각 스킬도 개별 검증하세요.

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py app-store-listing-creator
```

## 기여

기여 방법과 품질 기준은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요. 변경되는 플랫폼 사실을 스킬 본문에 고정하기보다, 작업 시점에 공식 문서를 확인하도록 설계하는 것을 우선합니다.

## License

[MIT License](LICENSE)
