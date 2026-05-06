# docker-ccstudio-ide 자동 연동 설정

docker-ccstudio-ide에서 새 버전이 빌드되면 action-ccstudio-ide에 자동으로 알림을 보내도록 설정합니다.

## 설정 방법

### 1. Personal Access Token 생성

1. GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token" 클릭
3. 권한 설정:
   - `repo` (Full control of private repositories) ✅
4. Token 복사

### 2. docker-ccstudio-ide에 Secret 추가

1. https://github.com/uoohyo/docker-ccstudio-ide/settings/secrets/actions
2. "New repository secret" 클릭
3. Name: `ACTION_REPO_TOKEN`
4. Value: 위에서 생성한 PAT 붙여넣기

### 3. build-all-versions.yml 수정

`.github/workflows/build-all-versions.yml` 파일의 `tag-latest` job 마지막에 추가:

```yaml
  notify-action-repo:
    name: Notify action-ccstudio-ide
    runs-on: ubuntu-latest
    needs: [detect-versions, build-and-push]
    if: success()
    steps:
      - name: Trigger action-ccstudio-ide sync
        run: |
          curl -X POST \
            -H "Authorization: token ${{ secrets.ACTION_REPO_TOKEN }}" \
            -H "Accept: application/vnd.github.v3+json" \
            https://api.github.com/repos/uoohyo/action-ccstudio-ide/dispatches \
            -d '{"event_type":"new-ccs-version"}'
          
          echo "✅ Notified action-ccstudio-ide to sync versions"
```

## 동작 방식

1. docker-ccstudio-ide에서 새 CCS 버전 빌드 완료
2. `notify-action-repo` job이 action-ccstudio-ide에 repository_dispatch 이벤트 전송
3. action-ccstudio-ide의 sync-versions.yml이 자동 실행
4. 새 버전 태그와 릴리즈가 자동 생성

## 테스트

docker-ccstudio-ide의 build-all-versions.yml을 수동으로 실행하면:
1. 빌드 완료 후 action-ccstudio-ide에 알림
2. action-ccstudio-ide의 Actions 탭에서 "Sync CCS Versions" 워크플로우 자동 실행 확인
