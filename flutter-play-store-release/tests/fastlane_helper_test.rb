# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../templates/FlutterPlayStoreRelease"

class FlutterPlayStoreReleaseHelperTest < Minitest::Test
  FPRS = FlutterPlayStoreRelease

  def setup
    @tmp = Dir.mktmpdir("fprs-fastlane-test-")
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp) if File.directory?(@tmp)
  end

  def test_normalizes_only_approved_version_shapes
    assert_equal "1.2.3", FPRS.normalize_version_name(" v1.2.3 ")
    assert_equal "1.2.3-beta.1", FPRS.normalize_version_name("1.2.3-beta.1")
    %w[1.2 1.2.3+4 1.2.3-beta_1 release-1.2.3].each do |value|
      assert_raises(FPRS::ConfigurationError) { FPRS.normalize_version_name(value) }
    end
  end

  def test_version_name_precedence_and_exact_head_tag_rules
    assert_equal "2.0.0", FPRS.resolve_version_name(
      option: "v2.0.0", env: "3.0.0", exact_head_tags: ["4.0.0"], pubspec: "5.0.0+9"
    )
    assert_equal "3.0.0", FPRS.resolve_version_name(
      option: nil, env: "v3.0.0", exact_head_tags: ["4.0.0"], pubspec: "5.0.0+9"
    )
    assert_equal "1.2.3", FPRS.resolve_version_name(
      option: nil, env: nil, exact_head_tags: %w[v1.2.3 1.2.3], pubspec: "9.9.9+1"
    )
    assert_equal "4.5.6-beta.2", FPRS.resolve_version_name(
      option: nil, env: nil, exact_head_tags: ["v4.5.6-beta.2"], pubspec: "9.9.9+1"
    )
    assert_equal "5.0.0", FPRS.resolve_version_name(
      option: nil, env: nil, exact_head_tags: [], pubspec: "v5.0.0+9"
    )
    assert_raises(FPRS::ConfigurationError) do
      FPRS.resolve_version_name(
        option: nil, env: nil, exact_head_tags: %w[1.2.3 1.2.4], pubspec: "5.0.0"
      )
    end
    assert_raises(FPRS::ConfigurationError) do
      FPRS.resolve_version_name(
        option: nil, env: nil, exact_head_tags: %w[1.2.3 bad-tag], pubspec: "5.0.0"
      )
    end
  end

  def test_version_code_bounds_and_track_maximum
    assert_equal 1, FPRS.validate_version_code("1", source: "test")
    assert_equal 2_100_000_000, FPRS.validate_version_code(2_100_000_000, source: "test")
    [nil, "", "0", "-1", "1.0", "2100000001"].each do |value|
      assert_raises(FPRS::ConfigurationError) do
        FPRS.validate_version_code(value, source: "test")
      end
    end

    calls = []
    code = FPRS.next_active_track_code(
      track_names: %w[internal alpha internal production],
      fetch_track_codes: lambda do |track|
        calls << track
        { "internal" => [], "alpha" => [3, 11], "production" => [7] }.fetch(track)
      end
    )
    assert_equal 12, code
    assert_equal %w[internal alpha production], calls
  end

  def test_track_query_failures_empty_first_release_and_upper_bound_are_hard_failures
    assert_raises(FPRS::FirstReleaseRequiredError) do
      FPRS.next_active_track_code(track_names: %w[internal beta], fetch_track_codes: ->(_track) { [] })
    end
    error = assert_raises(FPRS::ExternalActionError) do
      FPRS.next_active_track_code(
        track_names: %w[internal beta],
        fetch_track_codes: lambda { |track| raise "transport failure" if track == "beta"; [1] }
      )
    end
    assert_match(/beta/, error.message)
    assert_raises(FPRS::ConfigurationError) do
      FPRS.next_active_track_code(
        track_names: ["production"],
        fetch_track_codes: ->(_track) { [2_100_000_000] }
      )
    end
  end

  def test_distribution_routing_derives_firebase_enablement
    assert_equal ["play-store"], FPRS.distribution_steps(target: "play-store", firebase_enabled: true)
    assert_equal ["firebase"], FPRS.distribution_steps(target: "firebase", firebase_enabled: false)
    assert_equal %w[play-store firebase], FPRS.distribution_steps(target: "both", firebase_enabled: false)
    assert_equal %w[play-store firebase], FPRS.distribution_steps(target: nil, firebase_enabled: true)
    assert_equal ["play-store"], FPRS.distribution_steps(target: nil, firebase_enabled: false)
    assert_raises(FPRS::ConfigurationError) do
      FPRS.distribution_steps(target: "unknown", firebase_enabled: false)
    end
  end

  def test_artifact_discovery_accepts_one_fresh_matching_nonempty_output
    root = make_project
    started = Time.now - 2
    aab = artifact(root, "bundle/demoRelease/app-demo-release.aab", "aab")
    File.utime(Time.now, Time.now, aab)
    assert_equal File.realpath(aab), FPRS.locate_fresh_artifact(
      project_root: root,
      build_started_at: started,
      prior_outputs: [],
      flavor: "demo",
      artifact_type: "AAB"
    )

    apk = artifact(root, "apk/demo/release/app-demo-release.apk", "apk")
    FileUtils.rm_f(aab)
    assert_equal File.realpath(apk), FPRS.locate_fresh_artifact(
      project_root: root,
      build_started_at: started,
      prior_outputs: [],
      flavor: "demo",
      artifact_type: "APK"
    )
  end

  def test_artifact_discovery_rejects_zero_multiple_stale_empty_prior_and_flavor_mismatch
    root = make_project
    started = Time.now
    assert_raises(FPRS::ArtifactError) do
      locate(root, started: started, flavor: nil, type: "AAB")
    end

    stale = artifact(root, "bundle/release/app-release.aab", "old")
    File.utime(started - 10, started - 10, stale)
    assert_raises(FPRS::ArtifactError) { locate(root, started: started, flavor: nil, type: "AAB") }
    FileUtils.rm_f(stale)

    empty = artifact(root, "bundle/release/app-release.aab", "")
    assert_raises(FPRS::ArtifactError) { locate(root, started: started - 1, flavor: nil, type: "AAB") }
    FileUtils.rm_f(empty)

    prior = artifact(root, "bundle/release/app-release.aab", "same")
    assert_raises(FPRS::ArtifactError) do
      FPRS.locate_fresh_artifact(
        project_root: root,
        build_started_at: started - 1,
        prior_outputs: [prior], flavor: nil, artifact_type: "AAB"
      )
    end
    FileUtils.rm_f(prior)

    artifact(root, "bundle/freeRelease/app-free-release.aab", "wrong flavor")
    assert_raises(FPRS::ArtifactError) { locate(root, started: started - 1, flavor: "paid", type: "AAB") }
    FileUtils.rm_rf(File.join(root, "build"))

    artifact(root, "bundle/release/app-release.aab", "one")
    artifact(root, "bundle/other/release.aab", "two")
    assert_raises(FPRS::ArtifactError) { locate(root, started: started - 1, flavor: nil, type: "AAB") }
  end

  def test_secret_precedence_strict_base64_modes_and_cleanup_ownership
    temp_root = File.join(@tmp, "private")
    Dir.mkdir(temp_root, 0o700)
    explicit = File.join(@tmp, "explicit.json")
    default = File.join(@tmp, "default.json")
    File.write(explicit, "explicit")
    File.write(default, "default")

    record = FPRS.resolve_secret(
      path_value: explicit,
      base64_value: Base64.strict_encode64("encoded"),
      default_path: default,
      label: "service account",
      temp_root: temp_root
    )
    assert_equal File.realpath(explicit), record.fetch(:path)
    refute record.fetch(:owned)

    assert_raises(FPRS::ConfigurationError) do
      FPRS.resolve_secret(
        path_value: File.join(@tmp, "missing"),
        base64_value: Base64.strict_encode64("encoded"), default_path: default,
        label: "service account", temp_root: temp_root
      )
    end

    generated = FPRS.resolve_secret(
      path_value: nil, base64_value: Base64.strict_encode64("encoded"), default_path: default,
      label: "service account", temp_root: temp_root
    )
    assert_equal "encoded", File.binread(generated.fetch(:path))
    assert_equal 0o600, File.stat(generated.fetch(:path)).mode & 0o777
    assert generated.fetch(:owned)
    FPRS.cleanup_owned_secrets([record, generated])
    assert File.exist?(explicit), "explicit path must be preserved"
    refute File.exist?(generated.fetch(:path)), "owned decoded secret must be removed"
  end

  def test_invalid_base64_and_missing_default_are_hard_failures
    temp_root = File.join(@tmp, "private")
    Dir.mkdir(temp_root, 0o700)
    assert_raises(FPRS::ConfigurationError) do
      FPRS.resolve_secret(
        path_value: nil, base64_value: "%%%", default_path: nil,
        label: "firebase credential", temp_root: temp_root
      )
    end
    assert_raises(FPRS::ConfigurationError) do
      FPRS.resolve_secret(
        path_value: nil, base64_value: nil, default_path: File.join(@tmp, "missing"),
        label: "firebase credential", temp_root: temp_root
      )
    end
  end

  def test_java_properties_escaping_and_validation
    assert_equal '\\ leading\\=value\\:hash\\#bang\\!slash\\\\snowman\\u2603',
      FPRS.java_properties_escape(" leading=value:hash#bang!slash\\snowman☃", label: "password")
    ["line\nbreak", "tab\tvalue", "nul\0value"].each do |value|
      error = assert_raises(FPRS::ConfigurationError) do
        FPRS.java_properties_escape(value, label: "secret label")
      end
      assert_match(/secret label/, error.message)
      refute_includes error.message, value
    end
  end

  def test_key_properties_are_private_absolute_and_escaped
    key = File.join(@tmp, "key store.jks")
    File.binwrite(key, "key")
    output = File.join(@tmp, "private.properties")
    FPRS.write_key_properties(
      path: output, keystore_path: key, store_password: "p=a", key_alias: " alias",
      key_password: "p:b"
    )
    assert_equal 0o600, File.stat(output).mode & 0o777
    text = File.read(output)
    assert_includes text, "storeFile=#{FPRS.java_properties_escape(File.realpath(key), label: "storeFile")}"
    assert_includes text, "storePassword=p\\=a"
    assert_includes text, "keyAlias=\\ alias"
    assert_includes text, "keyPassword=p\\:b"
  end

  def test_slack_payload_is_json_safe_and_contains_only_expected_fields
    payload = FPRS.slack_payload(
      repository: 'owner/"repo', version: "1.2.3", track: "internal",
      result: "SUCCESS", run_url: "https://example.test/run\n1",
      source_url: "https://example.test/commit"
    )
    parsed = JSON.parse(payload)
    assert_equal 'owner/"repo', parsed.fetch("repository")
    assert_equal "SUCCESS", parsed.fetch("result")
    assert_equal %w[repository result run_url source_url track version], parsed.keys.sort
  end

  private

  def make_project
    root = File.join(@tmp, "app")
    FileUtils.mkdir_p(File.join(root, "build", "app", "outputs"))
    root
  end

  def artifact(root, relative, content)
    path = File.join(root, "build", "app", "outputs", relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
    path
  end

  def locate(root, started:, flavor:, type:)
    FPRS.locate_fresh_artifact(
      project_root: root, build_started_at: started, prior_outputs: [],
      flavor: flavor, artifact_type: type
    )
  end
end

class FlutterPlayStoreReleaseCoordinatorTest < Minitest::Test
  FPRS = FlutterPlayStoreRelease

  class FakeActions
    attr_reader :calls, :logs
    attr_accessor :track_codes, :firebase_failure, :play_failure, :build_outputs,
                  :release_id, :firebase_clients_result, :commit_count,
                  :notify_failure
    attr_reader :signing_snapshot

    def initialize(project_root)
      @project_root = project_root
      @calls = []
      @logs = []
      @track_codes = { "internal" => [41], "alpha" => [], "beta" => [], "production" => [17] }
      @build_outputs = 1
      @release_id = "com.example.app"
      @firebase_clients_result = [{ package_name: "com.example.app", app_id: "1:123:android:abc" }]
      @commit_count = 12
      @signing_snapshot = nil
      @play_failure = nil
      @firebase_failure = nil
      @notify_failure = nil
    end

    def record(name, kwargs = {})
      @calls << [name, kwargs]
    end

    def exact_head_tags
      record(:exact_head_tags)
      []
    end

    def runtime_ruby_version
      "3.3.11"
    end

    def tool_available?(_name)
      true
    end

    def git_commit_count
      record(:git_commit_count)
      @commit_count
    end

    def prepare(run_tests:)
      record(:prepare, run_tests: run_tests)
      true
    end

    def flutter_build(artifact_type:, build_name:, build_number:, flavor:, target:, environment:)
      record(:flutter_build, artifact_type: artifact_type, build_name: build_name,
        build_number: build_number, flavor: flavor, target: target,
        environment: environment.dup)
      properties_path = environment["ANDROID_KEY_PROPERTIES_PATH"]
      @signing_snapshot = if properties_path
        {
          path: properties_path,
          mode: File.stat(properties_path).mode & 0o777,
          content: File.read(properties_path)
        }
      end
      return if @build_outputs.zero?

      @build_outputs.times do |index|
        extension = artifact_type.downcase
        kind = artifact_type == "AAB" ? "bundle" : "apk"
        variant = flavor ? "#{flavor}Release" : "release"
        name = flavor ? "app-#{flavor}-release" : "app-release"
        name = "#{name}-#{index}" if @build_outputs > 1
        path = File.join(@project_root, "build", "app", "outputs", kind, variant, "#{name}.#{extension}")
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, "artifact #{index}")
      end
    end

    def release_application_id(flavor:)
      record(:release_application_id, flavor: flavor)
      @release_id
    end

    def firebase_clients
      record(:firebase_clients)
      @firebase_clients_result
    end

    def google_play_track_version_codes(**kwargs)
      record(:google_play_track_version_codes, kwargs)
      @track_codes.fetch(kwargs.fetch(:track))
    end

    def upload_to_play_store(**kwargs)
      record(:upload_to_play_store, kwargs)
      raise @play_failure if @play_failure
      true
    end

    def firebase_app_distribution(**kwargs)
      record(:firebase_app_distribution, kwargs)
      raise @firebase_failure if @firebase_failure
      true
    end

    def notify_slack(webhook:, payload:)
      record(:notify_slack, webhook: webhook, payload: payload)
      raise @notify_failure if @notify_failure
      true
    end

    def log(level, message)
      @logs << [level, message]
    end
  end

  def setup
    @tmp = Dir.mktmpdir("fprs-coordinator-test-")
    @project = File.join(@tmp, "project")
    FileUtils.mkdir_p(File.join(@project, "android", "fastlane"))
    File.write(File.join(@project, "pubspec.yaml"), "name: sample\nversion: 1.4.0+14\n")
    File.write(File.join(@project, "android", "Gemfile"), 'gem "fastlane", "= 2.237.0"')
    File.write(File.join(@project, "android", "Gemfile.lock"), "fastlane (2.237.0)\nfastlane-plugin-firebase_app_distribution (1.0.0)\n")
    File.write(File.join(@project, "android", "fastlane", "Fastfile"), "lane :release do\nend\n")
    File.write(File.join(@project, "android", "fastlane", "Pluginfile"), 'gem "fastlane-plugin-firebase_app_distribution", "= 1.0.0"')
    FileUtils.mkdir_p(File.join(@project, "android", "fastlane", "lib"))
    File.write(File.join(@project, "android", "fastlane", "lib", "flutter_play_store_release.rb"), "module FlutterPlayStoreRelease\nend\n")
    @play_json = File.join(@tmp, "play.json")
    @firebase_json = File.join(@tmp, "firebase.json")
    service_json = JSON.generate(type: "service_account", client_email: "release@example.invalid", private_key: "test")
    File.write(@play_json, service_json)
    File.write(@firebase_json, service_json)
    @keystore = File.join(@tmp, "upload.jks")
    File.binwrite(@keystore, "test key")
    @actions = FakeActions.new(@project)
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp) if File.directory?(@tmp)
  end

  def test_play_release_queries_all_unique_tracks_builds_once_and_uses_exact_upload_parameters
    result = release(
      target: "play-store",
      env: common_env.merge(
        "PLAY_STORE_VERSION_TRACKS" => "alpha,internal,beta,production,alpha",
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json
      )
    )
    assert_equal "SUCCESS", result.fetch("status")
    assert_equal 42, build_call.fetch(:build_number)
    assert_equal "lib/main_release.dart", build_call.fetch(:target)
    assert_equal 1, calls(:flutter_build).length
    assert_equal %w[internal alpha beta production], calls(:google_play_track_version_codes).map { |call| call.fetch(:track) }
    calls(:google_play_track_version_codes).each do |call|
      assert_equal File.realpath(@play_json), call.fetch(:json_key)
      assert_equal "com.example.app", call.fetch(:package_name)
    end
    upload = calls(:upload_to_play_store).fetch(0)
    assert upload.fetch(:aab).end_with?(".aab")
    refute upload.key?(:aab_path)
    assert_equal "com.example.app", upload.fetch(:package_name)
    assert_equal "internal", upload.fetch(:track)
    assert_equal "completed", upload.fetch(:release_status)
    assert_equal "1.4.0", upload.fetch(:version_name)
    %i[skip_upload_metadata skip_upload_changelogs skip_upload_images skip_upload_screenshots].each do |key|
      assert_equal true, upload.fetch(key)
    end
    refute upload.key?(:rollout)
    refute_includes JSON.generate(result), @play_json
  end

  def test_firebase_only_never_queries_play_uses_local_code_and_accepts_apk
    result = release(
      target: "firebase",
      env: common_env.merge(
        "VERSION_CODE" => "77",
        "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK",
        "FIREBASE_APP_ID" => "1:123:android:abc",
        "FIREBASE_SERVICE_ACCOUNT_JSON_PATH" => @firebase_json,
        "FIREBASE_RELEASE_NOTES" => "Reviewed notes",
        "FIREBASE_TESTERS" => "one@example.test",
        "FIREBASE_TESTER_GROUPS" => "qa"
      )
    )
    assert_equal "SUCCESS", result.fetch("status")
    assert_empty calls(:google_play_track_version_codes)
    assert_empty calls(:upload_to_play_store)
    assert_equal "APK", build_call.fetch(:artifact_type)
    assert_equal 77, build_call.fetch(:build_number)
    firebase = calls(:firebase_app_distribution).fetch(0)
    assert_equal "1:123:android:abc", firebase.fetch(:app)
    assert_equal "APK", firebase.fetch(:android_artifact_type)
    assert firebase.fetch(:android_artifact_path).end_with?(".apk")
    assert_equal File.realpath(@firebase_json), firebase.fetch(:service_credentials_file)
    assert_equal "Reviewed notes", firebase.fetch(:release_notes)
    refute firebase.key?(:release_notes_file)
    assert_equal "one@example.test", firebase.fetch(:testers)
    assert_equal "qa", firebase.fetch(:groups)
  end

  def test_firebase_local_code_falls_back_to_pubspec_then_positive_git_count
    release(
      target: "firebase",
      env: common_env.merge(firebase_env).reject { |key, _| key == "VERSION_CODE" }
    )
    assert_equal 14, build_call.fetch(:build_number)

    File.write(File.join(@project, "pubspec.yaml"), "name: sample\nversion: 1.4.0\n")
    @actions = FakeActions.new(@project)
    release(target: "firebase", env: common_env.merge(firebase_env))
    assert_equal 12, build_call.fetch(:build_number)
  end

  def test_both_builds_once_reuses_aab_and_firebase_failure_is_nonzero_partial_success
    @actions.firebase_failure = RuntimeError.new("firebase adapter failed at /secret/path")
    result_path = File.join(@tmp, "result.json")
    error = assert_raises(FPRS::PartialSuccessError) do
      release(
        target: "both",
        env: common_env.merge(firebase_env,
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
          "RELEASE_RESULT_PATH" => result_path,
          "SLACK_WEBHOOK_URL" => "https://hooks.example.invalid/secret",
          "SLACK_NOTIFY_FAILURE" => "true")
      )
    end
    assert_match(/PARTIAL_SUCCESS/, error.message)
    assert_equal 1, calls(:flutter_build).length
    assert_equal 1, calls(:upload_to_play_store).length
    assert_equal 1, calls(:firebase_app_distribution).length
    assert_equal calls(:upload_to_play_store).first.fetch(:aab),
      calls(:firebase_app_distribution).first.fetch(:android_artifact_path)
    result = JSON.parse(File.read(result_path))
    assert_equal "PARTIAL_SUCCESS", result.fetch("status")
    assert_equal ["play-store"], result.fetch("successful_destinations")
    assert_equal "firebase", result.fetch("failed_destination")
    refute_includes JSON.generate(result), "/secret/path"
    assert_equal 1, calls(:notify_slack).length
  end

  def test_both_rejects_apk_before_build_or_network
    assert_raises(FPRS::ConfigurationError) do
      release(
        target: "both",
        env: common_env.merge(firebase_env,
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
          "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK")
      )
    end
    assert_empty calls(:flutter_build)
    assert_empty calls(:google_play_track_version_codes)
  end

  def test_firebase_aab_requires_link_confirmation
    assert_raises(FPRS::ConfigurationError) do
      release(
        target: "firebase",
        env: common_env.merge(firebase_env.reject { |key, _| key == "CONFIRM_FIREBASE_AAB_PLAY_LINKED" })
      )
    end
    assert_empty calls(:firebase_app_distribution)
    release(
      target: "firebase",
      env: common_env.merge(firebase_env, "CONFIRM_FIREBASE_AAB_PLAY_LINKED" => "true")
    )
    assert_equal 1, calls(:firebase_app_distribution).length
  end

  def test_detected_firebase_mismatch_cannot_be_overridden_but_absent_evidence_can_be_confirmed
    @actions.firebase_clients_result = [{ package_name: "com.other.app", app_id: "1:123:android:other" }]
    assert_raises(FPRS::ConfigurationError) do
      release(
        target: "firebase",
        env: common_env.merge(firebase_env,
          "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK",
          "CONFIRM_FIREBASE_PACKAGE_MATCH" => "true")
      )
    end
    assert_empty calls(:firebase_app_distribution)

    @actions = FakeActions.new(@project)
    @actions.firebase_clients_result = []
    assert_raises(FPRS::ConfigurationError) do
      release(target: "firebase", env: common_env.merge(firebase_env, "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK"))
    end
    @actions = FakeActions.new(@project)
    @actions.firebase_clients_result = []
    release(
      target: "firebase",
      env: common_env.merge(firebase_env,
        "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK",
        "CONFIRM_FIREBASE_PACKAGE_MATCH" => "true")
    )
    assert_equal 1, calls(:firebase_app_distribution).length
  end

  def test_failed_preflight_calls_no_network_adapter_and_target_credentials_are_isolated
    bad = common_env.merge("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => File.join(@tmp, "missing"))
    assert_raises(FPRS::ConfigurationError) { release(target: "play-store", env: bad) }
    assert_empty calls(:google_play_track_version_codes)
    assert_empty calls(:upload_to_play_store)

    @actions = FakeActions.new(@project)
    release(
      target: "firebase",
      env: common_env.merge(firebase_env,
        "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK",
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => File.join(@tmp, "missing"))
    )
    assert_empty calls(:google_play_track_version_codes)

    @actions = FakeActions.new(@project)
    release(
      target: "play-store",
      env: common_env.merge(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
        "FIREBASE_SERVICE_ACCOUNT_JSON_PATH" => File.join(@tmp, "missing-firebase"))
    )
    assert_empty calls(:firebase_app_distribution)
  end


  def test_build_only_uses_local_version_fallback_and_never_queries_play
    artifact = FPRS.build_only(
      options: { target: "lib/main_release.dart" }, env: common_env,
      actions: @actions, project_root: @project
    )
    assert artifact.end_with?(".aab")
    assert_equal 14, build_call.fetch(:build_number)
    assert_equal "lib/main_release.dart", build_call.fetch(:target)
    assert_empty calls(:google_play_track_version_codes)
    assert_empty calls(:upload_to_play_store)
  end

  def test_base64_keystore_generates_private_override_and_cleans_every_owned_file
    env = common_env.reject { |key, _| key == "ANDROID_KEYSTORE_PATH" }.merge(
      "ANDROID_KEYSTORE_BASE64" => Base64.strict_encode64("base64 key bytes"),
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json
    )
    release(target: "play-store", env: env)
    snapshot = @actions.signing_snapshot
    assert_equal 0o600, snapshot.fetch(:mode)
    assert_includes snapshot.fetch(:content), "storePassword=store\\=pass"
    assert_includes snapshot.fetch(:content), "keyAlias=\\ upload"
    assert_includes snapshot.fetch(:content), "keyPassword=key\\:pass"
    store_file = snapshot.fetch(:content)[/^storeFile=(.+)$/, 1]
    refute File.exist?(snapshot.fetch(:path)), "generated key.properties override leaked"
    refute File.exist?(store_file), "decoded keystore leaked"
  end

  def test_ci_uses_the_private_override_when_workspace_is_clean
    release(
      target: "play-store",
      env: common_env.merge(
        "CI" => "true", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json)
    )
    snapshot = @actions.signing_snapshot
    assert snapshot
    assert_equal 0o600, snapshot.fetch(:mode)
    refute File.exist?(snapshot.fetch(:path))
  end

  def test_invalid_service_account_json_stops_before_any_network_action
    invalid = File.join(@tmp, "invalid-service.json")
    File.write(invalid, JSON.generate(type: "authorized_user", client_email: "wrong@example.test"))
    assert_raises(FPRS::ConfigurationError) do
      release(
        target: "play-store",
        env: common_env.merge("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => invalid)
      )
    end
    assert_empty calls(:google_play_track_version_codes)
    assert_empty calls(:flutter_build)
  end

  def test_both_package_mismatch_stops_before_play_track_query
    @actions.firebase_clients_result = [{ package_name: "com.wrong", app_id: "wrong" }]
    assert_raises(FPRS::ConfigurationError) do
      release(
        target: "both",
        env: common_env.merge(firebase_env,
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
          "CONFIRM_FIREBASE_PACKAGE_MATCH" => "true")
      )
    end
    assert_empty calls(:google_play_track_version_codes)
    assert_empty calls(:flutter_build)
  end

  def test_firebase_only_ignores_play_release_policy_inputs
    release(
      target: "firebase",
      env: common_env.merge(firebase_env,
        "FIREBASE_ANDROID_ARTIFACT_TYPE" => "APK",
        "PLAY_STORE_RELEASE_STATUS" => "halted",
        "PLAY_STORE_TRACK" => "production")
    )
    assert_equal 1, calls(:firebase_app_distribution).length
    assert_empty calls(:google_play_track_version_codes)
  end

  def test_release_status_rollout_and_production_confirmation
    in_progress = common_env.merge(
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
      "PLAY_STORE_RELEASE_STATUS" => "inProgress",
      "PLAY_STORE_ROLLOUT" => "0.2"
    )
    release(target: "play-store", env: in_progress)
    assert_equal 0.2, calls(:upload_to_play_store).first.fetch(:rollout)

    %w[0 1 -0.1 nope].each do |rollout|
      @actions = FakeActions.new(@project)
      assert_raises(FPRS::ConfigurationError) do
        release(target: "play-store", env: in_progress.merge("PLAY_STORE_ROLLOUT" => rollout))
      end
      assert_empty calls(:google_play_track_version_codes)
    end

    %w[draft completed].each do |status|
      @actions = FakeActions.new(@project)
      release(
        target: "play-store",
        env: common_env.merge(
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
          "PLAY_STORE_RELEASE_STATUS" => status,
          "PLAY_STORE_ROLLOUT" => "0.2")
      )
      refute calls(:upload_to_play_store).first.key?(:rollout)
    end

    @actions = FakeActions.new(@project)
    assert_raises(FPRS::ConfigurationError) do
      release(target: "play-store", env: common_env.merge(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
        "PLAY_STORE_RELEASE_STATUS" => "halted"))
    end
    assert_empty calls(:google_play_track_version_codes)

    @actions = FakeActions.new(@project)
    assert_raises(FPRS::ConfigurationError) do
      release(target: "play-store", env: common_env.merge(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
        "PLAY_STORE_TRACK" => "production"))
    end
    @actions = FakeActions.new(@project)
    release(target: "play-store", env: common_env.merge(
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
      "PLAY_STORE_TRACK" => "production",
      "CONFIRM_PRODUCTION_DEPLOY" => "true"))
    assert_equal "production", calls(:upload_to_play_store).first.fetch(:track)
  end

  def test_ci_signing_requires_all_values_and_refuses_workspace_key_properties
    ci = common_env.reject { |key, _| signing_env.key?(key) }.merge(
      "CI" => "true", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json
    )
    assert_raises(FPRS::ConfigurationError) { release(target: "play-store", env: ci) }
    assert_empty calls(:google_play_track_version_codes)

    File.write(File.join(@project, "android", "key.properties"), "user owned")
    @actions = FakeActions.new(@project)
    assert_raises(FPRS::ConfigurationError) do
      release(target: "play-store", env: ci.merge(signing_env))
    end
    assert_equal "user owned", File.read(File.join(@project, "android", "key.properties"))
  end

  def test_local_complete_key_properties_fallback_is_preserved
    key_properties = File.join(@project, "android", "key.properties")
    File.write(key_properties, <<~PROPERTIES)
      storeFile=#{@keystore}
      storePassword=test
      keyAlias=upload
      keyPassword=test
    PROPERTIES
    env = common_env.reject { |key, _| signing_env.key?(key) }.merge(
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json
    )
    release(target: "play-store", env: env)
    assert File.exist?(key_properties)
    assert_includes File.read(key_properties), "keyAlias=upload"
  end

  def test_failed_build_restores_prior_artifact_and_removes_new_candidates
    prior = File.join(@project, "build", "app", "outputs", "bundle", "release", "app-release.aab")
    FileUtils.mkdir_p(File.dirname(prior))
    File.binwrite(prior, "prior bytes")
    @actions.build_outputs = 2
    assert_raises(FPRS::ArtifactError) do
      release(target: "play-store", env: common_env.merge("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json))
    end
    assert_equal "prior bytes", File.binread(prior)
    assert_equal [prior], Dir.glob(File.join(@project, "build", "app", "outputs", "**", "*.aab"))
  end

  def test_failed_flavor_build_preserves_unrelated_variant_outputs
    unrelated = File.join(@project, "build", "app", "outputs", "bundle", "freeRelease", "app-free-release.aab")
    FileUtils.mkdir_p(File.dirname(unrelated))
    File.binwrite(unrelated, "free variant bytes")
    @actions.build_outputs = 2
    assert_raises(FPRS::ArtifactError) do
      release(
        target: "play-store",
        env: common_env.merge(
          "FLUTTER_FLAVOR" => "paid",
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json)
      )
    end
    assert_equal "free variant bytes", File.binread(unrelated)
    assert_equal [unrelated], Dir.glob(File.join(@project, "build", "app", "outputs", "**", "*.aab"))
  end

  def test_failed_build_cleans_base64_keystore_and_private_properties
    @actions.build_outputs = 2
    assert_raises(FPRS::ArtifactError) do
      release(
        target: "play-store",
        env: common_env.reject { |key, _| key == "ANDROID_KEYSTORE_PATH" }.merge(
          "ANDROID_KEYSTORE_BASE64" => Base64.strict_encode64("temporary key"),
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json)
      )
    end
    snapshot = @actions.signing_snapshot
    store_file = snapshot.fetch(:content)[/^storeFile=(.+)$/, 1]
    refute File.exist?(snapshot.fetch(:path))
    refute File.exist?(store_file)
  end

  def test_result_schema_redacts_credentials_and_notification_owner_is_singular
    result_path = File.join(@tmp, "result.json")
    release(
      target: "play-store",
      env: common_env.merge(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
        "RELEASE_RESULT_PATH" => result_path,
        "SLACK_WEBHOOK_URL" => "https://hooks.example.invalid/private",
        "SLACK_NOTIFY_SUCCESS" => "true",
        "SLACK_NOTIFICATION_OWNER" => "github-actions")
    )
    result = JSON.parse(File.read(result_path))
    assert_equal 1, result.fetch("schema_version")
    assert_equal "SUCCESS", result.fetch("status")
    assert_equal ["play-store"], result.fetch("successful_destinations")
    refute_includes File.read(result_path), @play_json
    assert_empty calls(:notify_slack)
  end

  def test_failure_result_names_failed_destination_and_preserves_original_exception_class
    @actions.play_failure = RuntimeError.new("secret adapter detail #{@play_json}")
    result_path = File.join(@tmp, "failure-result.json")
    assert_raises(FPRS::ExternalActionError) do
      release(
        target: "play-store",
        env: common_env.merge(
          "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
          "RELEASE_RESULT_PATH" => result_path)
      )
    end
    result = JSON.parse(File.read(result_path))
    assert_equal "FAILURE", result.fetch("status")
    assert_equal "play-store", result.fetch("failed_destination")
    assert_empty result.fetch("successful_destinations")
    refute_includes File.read(result_path), @play_json
  end

  def test_slack_failure_never_replaces_a_successful_release_result
    @actions.notify_failure = RuntimeError.new("Slack unavailable")
    result = release(
      target: "play-store",
      env: common_env.merge(
        "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json,
        "SLACK_WEBHOOK_URL" => "https://hooks.example.invalid/private",
        "SLACK_NOTIFY_SUCCESS" => "true")
    )
    assert_equal "SUCCESS", result.fetch("status")
    assert_equal 1, calls(:notify_slack).length
    assert @actions.logs.any? { |level, message| level == :warn && message.include?("Slack notification failed") }
  end

  def test_play_failures_return_redacted_operator_guidance_by_failure_class
    cases = {
      "HTTP 403 permission denied #{@play_json}" => /authentication or permission/,
      "No app with given bundle id; first upload required #{@play_json}" => /first-release\/manual bootstrap/,
      "Version code has already been used #{@play_json}" => /active-track version code/
    }
    cases.each do |message, expected|
      @actions = FakeActions.new(@project)
      @actions.play_failure = RuntimeError.new(message)
      error = assert_raises(FPRS::ExternalActionError) do
        release(
          target: "play-store",
          env: common_env.merge("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" => @play_json)
        )
      end
      assert_match expected, error.message
      refute_includes error.message, @play_json
    end
  end

  def test_doctor_warns_without_credentials_and_fails_deploy_before_network
    report = FPRS.doctor(
      env: { "APP_PACKAGE_NAME" => "com.example.app" }, target: "play-store",
      context: "doctor", actions: @actions, project_root: @project
    )
    assert report.any? { |entry| entry.fetch(:level) == "WARN" }

    assert_raises(FPRS::PreflightError) do
      FPRS.doctor(
        env: { "APP_PACKAGE_NAME" => "com.example.app" }, target: "play-store",
        context: "deploy", actions: @actions, project_root: @project
      )
    end
    assert_empty calls(:google_play_track_version_codes)
  end

  private

  def release(target:, env:)
    FPRS.release(
      options: { distribution_target: target }, env: env,
      actions: @actions, project_root: @project
    )
  end

  def calls(name)
    @actions.calls.select { |entry| entry.first == name }.map(&:last)
  end

  def build_call
    calls(:flutter_build).fetch(0)
  end

  def signing_env
    {
      "ANDROID_KEYSTORE_PATH" => @keystore,
      "ANDROID_KEYSTORE_PASSWORD" => "store=pass",
      "ANDROID_KEY_ALIAS" => " upload",
      "ANDROID_KEY_PASSWORD" => "key:pass"
    }
  end

  def common_env
    signing_env.merge(
      "APP_PACKAGE_NAME" => "com.example.app",
      "VERSION_NAME" => "1.4.0",
      "PLAY_STORE_TRACK" => "internal",
      "RELEASE_DART_TARGET" => "lib/main_release.dart"
    )
  end

  def firebase_env
    {
      "FIREBASE_APP_ID" => "1:123:android:abc",
      "FIREBASE_SERVICE_ACCOUNT_JSON_PATH" => @firebase_json,
      "CONFIRM_FIREBASE_AAB_PLAY_LINKED" => "true"
    }
  end
end

class FlutterPlayStoreReleaseFastfileTest < Minitest::Test
  FPRS = FlutterPlayStoreRelease

  class AdapterDsl
    attr_reader :calls

    def initialize
      @calls = []
    end

    def method_missing(name, *args, **kwargs, &block)
      @calls << [name, args, kwargs]
      return [] if name == :google_play_track_version_codes
      true
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  class FastfileHarness
    attr_reader :lanes, :error_hook

    def initialize
      @lanes = {}
    end

    def opt_out_usage; end
    def default_platform(_name); end
    def desc(_text); end

    def platform(_name, &block)
      instance_eval(&block)
    end

    def lane(name, &block)
      @lanes[name] = block
    end

    def error(&block)
      @error_hook = block
    end
  end

  def test_fastlane_adapter_maps_current_action_parameter_names
    dsl = AdapterDsl.new
    adapter = FPRS::FastlaneAdapter.new(dsl)
    adapter.google_play_track_version_codes(json_key: "/tmp/play.json", package_name: "com.example", track: "beta")
    adapter.upload_to_play_store(
      json_key: "/tmp/play.json", aab: "/tmp/app.aab", package_name: "com.example",
      track: "beta", release_status: "completed", version_name: "1.0.0",
      skip_upload_metadata: true, skip_upload_changelogs: true,
      skip_upload_images: true, skip_upload_screenshots: true
    )
    adapter.firebase_app_distribution(
      app: "1:2:android:3", android_artifact_type: "APK",
      android_artifact_path: "/tmp/app.apk", service_credentials_file: "/tmp/firebase.json",
      release_notes: "notes", testers: "a@example.test", groups: "qa"
    )
    assert_equal :google_play_track_version_codes, dsl.calls[0][0]
    assert_equal :upload_to_play_store, dsl.calls[1][0]
    assert dsl.calls[1][2].key?(:aab)
    refute dsl.calls[1][2].key?(:aab_path)
    assert_equal :firebase_app_distribution, dsl.calls[2][0]
  end

  def test_fastlane_adapter_sends_slack_body_on_stdin_and_keeps_webhook_out_of_arguments
    webhook = "https://hooks.example.invalid/private-token"
    payload = JSON.generate(text: "release payload secret")
    observed_config = nil
    runner = lambda do |command, stdin|
      refute command.any? { |argument| argument.include?(webhook) }
      refute command.any? { |argument| argument.include?(payload) }
      assert_equal payload, stdin
      assert_equal ["--data-binary", "@-"], command.last(2)
      config_path = command.fetch(command.index("--config") + 1)
      observed_config = config_path
      assert_includes File.read(config_path), webhook
      ["", "", Struct.new(:success?).new(true)]
    end
    adapter = FPRS::FastlaneAdapter.new(AdapterDsl.new, command_runner: runner)
    assert adapter.notify_slack(webhook: webhook, payload: payload)
    refute File.exist?(observed_config), "temporary curl config leaked"
  end

  def test_fastlane_adapter_prepare_runs_build_runner_analyze_and_optional_tests
    Dir.mktmpdir("fprs-adapter-") do |root|
      File.write(File.join(root, "pubspec.yaml"), "name: app\ndev_dependencies:\n  build_runner: ^2.4.0\n")
      dsl = AdapterDsl.new
      FPRS::FastlaneAdapter.new(dsl, project_root: root).prepare(run_tests: true)
      commands = dsl.calls.select { |entry| entry.first == :sh }.map { |entry| entry[1] }
      assert_includes commands, %w[flutter pub get]
      assert_includes commands, %w[flutter pub run build_runner build --delete-conflicting-outputs]
      assert_includes commands, %w[flutter analyze]
      assert_includes commands, %w[flutter test]
    end
  end

  def test_fastlane_adapter_resolves_kotlin_flavor_and_release_application_id_suffixes
    Dir.mktmpdir("fprs-gradle-id-") do |root|
      app = File.join(root, "android", "app")
      FileUtils.mkdir_p(app)
      File.write(File.join(app, "build.gradle.kts"), <<~GRADLE)
        android {
          defaultConfig {
            applicationId = "com.example.app"
          }
          productFlavors {
            create("demo") {
              dimension = "market"
              resValue("string", "label", "brace { in a string }")
              applicationIdSuffix = ".demo"
            }
          }
          buildTypes {
            getByName("release") {
              applicationIdSuffix = ".prod"
            }
          }
        }
      GRADLE
      adapter = FPRS::FastlaneAdapter.new(AdapterDsl.new, project_root: root)
      assert_equal "com.example.app.demo.prod", adapter.release_application_id(flavor: "demo")
    end
  end

  def test_fastfile_declares_every_public_lane_and_delegates_release_lanes
    source = File.read(File.expand_path("../templates/Fastfile", __dir__))
    %w[doctor prepare build release release_play_store firebase_distribution].each do |lane|
      assert_match(/lane\s+:#{Regexp.escape(lane)}\s+do/, source)
    end
    assert_match(/release_play_store.*execute_fastlane_lane\(:release/m, source)
    assert_match(/firebase_distribution.*execute_fastlane_lane\(:release/m, source)
  end

  def test_direct_and_delegate_lanes_execute_one_coordinator_call_with_fixed_targets
    source = File.read(File.expand_path("../templates/Fastfile", __dir__))
      .sub(/^require_relative .*\n/, "")
    harness = FastfileHarness.new
    harness.instance_eval(source, File.expand_path("../templates/Fastfile", __dir__))
    calls = []
    singleton = FPRS.singleton_class
    original = FPRS.method(:execute_fastlane_lane)
    singleton.send(:define_method, :execute_fastlane_lane) do |lane, options, dsl|
      calls << [lane, options, dsl]
    end
    begin
      harness.lanes.fetch(:release).call({ version_name: "1.2.3" })
      harness.lanes.fetch(:release_play_store).call({})
      harness.lanes.fetch(:firebase_distribution).call({})
    ensure
      singleton.send(:define_method, :execute_fastlane_lane, original)
    end
    assert_equal 3, calls.length
    assert_equal :release, calls[0][0]
    assert_equal "play-store", calls[1][1].fetch(:distribution_target)
    assert_equal "firebase", calls[2][1].fetch(:distribution_target)
    assert calls.all? { |entry| entry[2].equal?(harness) }
  end
end
