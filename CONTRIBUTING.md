# Contributing

기여를 환영합니다. 각 스킬은 한 가지 분명한 책임을 가져야 하며, 에이전트가 실제 프로젝트를 확인하고 검증 가능한 결과를 내도록 안내해야 합니다.

## 원칙

- 바뀔 수 있는 플랫폼 규격, 정책, API는 작업 시점의 공식 문서로 확인합니다.
- 진단과 실제 변경 권한을 구분하고 사용자의 관련 없는 변경을 보존합니다.
- 순위, 스토어 승인, 성능 향상, AI 검색 노출을 보장하지 않습니다.
- 생성물, 캐시, 비밀값, 개인 컴퓨터의 절대 경로를 커밋하지 않습니다.
- 긴 조건부 지식은 `references/`로 분리하고 `SKILL.md`에서 언제 읽을지 명시합니다.

## 변경 절차

1. 스킬 폴더 이름과 frontmatter의 `name`을 동일한 소문자 hyphen-case로 작성합니다.
2. `description`에 무엇을 하는지와 언제 호출해야 하는지를 모두 적습니다.
3. `agents/openai.yaml`의 표시 이름, 25–64자 설명, `$skill-name`이 포함된 기본 프롬프트를 맞춥니다.
4. 아래 검증을 실행합니다.

```bash
python3 scripts/validate_skills.py
python3 /path/to/skill-creator/scripts/quick_validate.py <skill-directory>
```

5. 변경 목적, 검증 결과, 남은 제약을 pull request에 기록합니다.

## English summary

Keep each skill focused, verify unstable facts against current primary sources, preserve user work, and run both the repository validator and the official skill validator before opening a pull request.

