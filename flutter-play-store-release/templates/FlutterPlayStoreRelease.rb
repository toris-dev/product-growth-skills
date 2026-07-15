# frozen_string_literal: true

# Shared, dependency-free release logic for the generated Android Fastlane lanes.
# External services are reached only through FastlaneAdapter after preflight succeeds.
require "base64"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "tempfile"
require "tmpdir"

module FlutterPlayStoreRelease
  MAX_VERSION_CODE = 2_100_000_000
  VERSION_NAME_PATTERN = /\Av?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?\z/.freeze
  DEFAULT_PLAY_TRACKS = %w[internal alpha beta production].freeze
  RESULT_SCHEMA_VERSION = 1

  class ReleaseError < StandardError; end
  class ConfigurationError < ReleaseError; end
  class PreflightError < ConfigurationError; end
  class ArtifactError < ReleaseError; end
  class ExternalActionError < ReleaseError; end
  class FirstReleaseRequiredError < ReleaseError; end
  class PartialSuccessError < ReleaseError; end

  class << self
    def normalize_version_name(raw)
      value = raw.to_s.strip
      match = VERSION_NAME_PATTERN.match(value)
      raise ConfigurationError, "version name must match v?MAJOR.MINOR.PATCH with an optional dot-separated prerelease" unless match

      core = [match[1], match[2], match[3]].join(".")
      match[4] ? "#{core}-#{match[4]}" : core
    end

    def resolve_version_name(option:, env:, exact_head_tags:, pubspec:)
      return normalize_version_name(option) unless blank?(option)
      return normalize_version_name(env) unless blank?(env)

      tags = Array(exact_head_tags).map { |tag| tag.to_s.strip }.reject(&:empty?)
      unless tags.empty?
        normalized = tags.map do |tag|
          normalize_version_name(tag)
        rescue ConfigurationError
          raise ConfigurationError, "exact HEAD tags contain an unsupported or ambiguous version tag"
        end
        unique = normalized.uniq
        raise ConfigurationError, "exact HEAD tags resolve to conflicting version names" unless unique.length == 1
        return unique.first
      end

      pubspec_value = pubspec.to_s.strip
      pubspec_value = pubspec_value.split("+", 2).first
      normalize_version_name(pubspec_value)
    end

    def validate_version_code(raw, source:)
      value = raw.to_s.strip
      unless value.match?(/\A[0-9]+\z/)
        raise ConfigurationError, "#{source} must be a positive integer version code"
      end
      number = Integer(value, 10)
      unless number.between?(1, MAX_VERSION_CODE)
        raise ConfigurationError, "#{source} must be between 1 and #{MAX_VERSION_CODE}"
      end
      number
    rescue ArgumentError
      raise ConfigurationError, "#{source} must be a positive integer version code"
    end

    # Returns the next active-track code. Google Play does not expose an
    # authoritative allocator for every code ever used, so callers must serialize
    # selection and upload and handle a reuse rejection explicitly.
    def next_active_track_code(track_names:, fetch_track_codes:)
      tracks = ordered_unique(Array(track_names).map { |track| track.to_s.strip }.reject(&:empty?))
      raise ConfigurationError, "at least one Play track is required" if tracks.empty?

      codes = []
      tracks.each do |track|
        begin
          response = fetch_track_codes.call(track)
        rescue ReleaseError
          raise
        rescue StandardError => error
          raise ExternalActionError, "could not query Play track #{track}: #{classify_play_failure(error)}"
        end
        unless response.is_a?(Array)
          raise ExternalActionError, "Play track #{track} returned an invalid version-code response"
        end
        response.each do |raw_code|
          codes << validate_version_code(raw_code, source: "Play track #{track} version code")
        end
      end

      if codes.empty?
        raise FirstReleaseRequiredError,
          "all configured Play tracks are empty; complete the first-release/manual-bootstrap checklist"
      end
      maximum = codes.max
      if maximum >= MAX_VERSION_CODE
        raise ConfigurationError, "the next active-track code would exceed #{MAX_VERSION_CODE}"
      end
      maximum + 1
    end

    def distribution_steps(target:, firebase_enabled:)
      normalized = target.to_s.strip
      if normalized.empty?
        return truthy?(firebase_enabled) ? %w[play-store firebase] : ["play-store"]
      end
      case normalized
      when "play-store" then ["play-store"]
      when "firebase" then ["firebase"]
      when "both" then %w[play-store firebase]
      else
        raise ConfigurationError, "DISTRIBUTION_TARGET must be play-store, firebase, or both"
      end
    end

    def locate_fresh_artifact(project_root:, build_started_at:, prior_outputs:, flavor:, artifact_type:)
      root = canonical_directory(project_root, "project root")
      type = normalize_artifact_type(artifact_type)
      pattern = type == "AAB" ? "bundle/**/*.aab" : "apk/**/*.apk"
      output_root = File.join(root, "build", "app", "outputs")
      prior = Array(prior_outputs).map do |path|
        expanded = File.expand_path(path.to_s)
        File.exist?(expanded) ? File.realpath(expanded) : expanded
      end
      started_at = build_started_at.respond_to?(:to_f) ? build_started_at.to_f : Float(build_started_at)
      selected_flavor = flavor.to_s.strip.downcase

      candidates = Dir.glob(File.join(output_root, pattern)).select do |path|
        expanded = File.expand_path(path)
        next false if prior.include?(expanded)
        next false unless safe_regular_file?(expanded)
        next false unless File.size(expanded).positive?
        next false if File.mtime(expanded).to_f < started_at
        next true if selected_flavor.empty?

        expanded.downcase.include?(selected_flavor)
      end
      candidates.sort!
      if candidates.length != 1
        raise ArtifactError,
          "expected exactly one fresh #{type} artifact for the selected variant; found #{candidates.length}"
      end
      File.realpath(candidates.first)
    rescue Errno::ENOENT, Errno::ENOTDIR, ArgumentError => error
      raise ArtifactError, "could not validate the requested build artifact: #{error.class}"
    end

    def resolve_secret(path_value:, base64_value:, default_path:, label:, temp_root:)
      root = canonical_directory(temp_root, "owned secret root")
      ensure_private_directory!(root)

      unless blank?(path_value)
        return { path: canonical_secret_file(path_value, label), owned: false, label: label.to_s }
      end

      unless blank?(base64_value)
        begin
          decoded = Base64.strict_decode64(base64_value.to_s)
        rescue ArgumentError
          raise ConfigurationError, "#{label} Base64 input is invalid"
        end
        raise ConfigurationError, "#{label} Base64 input decoded to an empty file" if decoded.empty?

        filename = "#{safe_label(label)}-#{SecureRandom.hex(12)}"
        path = File.join(root, filename)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.binmode
          file.write(decoded)
          file.flush
          file.fsync
        end
        File.chmod(0o600, path)
        return { path: path, owned: true, label: label.to_s, root: root }
      end

      unless blank?(default_path)
        return { path: canonical_secret_file(default_path, label), owned: false, label: label.to_s }
      end

      raise ConfigurationError, "#{label} is required"
    end

    def java_properties_escape(value, label:)
      string = value.to_s
      escaped = +""
      leading = true
      string.each_codepoint do |codepoint|
        if codepoint.zero? || codepoint < 0x20 || codepoint == 0x7f
          raise ConfigurationError, "#{label} contains a prohibited control character"
        end
        character = codepoint.chr(Encoding::UTF_8)
        if character == " " && leading
          escaped << "\\ "
        elsif character == "\\"
          escaped << "\\\\"
        elsif "=:#!".include?(character)
          escaped << "\\#{character}"
        elsif codepoint > 0x7e
          append_java_unicode_escape(escaped, codepoint)
        else
          escaped << character
        end
        leading = false unless character == " "
      end
      escaped
    end

    def write_key_properties(path:, keystore_path:, store_password:, key_alias:, key_password:)
      output = File.expand_path(path.to_s)
      key_path = canonical_secret_file(keystore_path, "Android keystore")
      FileUtils.mkdir_p(File.dirname(output), mode: 0o700)
      raise ConfigurationError, "generated key properties path already exists" if File.exist?(output) || File.symlink?(output)

      lines = {
        "storeFile" => key_path,
        "storePassword" => store_password,
        "keyAlias" => key_alias,
        "keyPassword" => key_password
      }.map do |name, value|
        raise ConfigurationError, "#{name} is required" if blank?(value)
        "#{name}=#{java_properties_escape(value, label: name)}"
      end
      File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(lines.join("\n"))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.chmod(0o600, output)
      output
    end

    def cleanup_owned_secrets(secret_records)
      Array(secret_records).reverse_each do |record|
        next unless record.is_a?(Hash) && record[:owned]
        path = record[:path].to_s
        root = record[:root].to_s
        next if path.empty? || root.empty? || File.symlink?(path) || File.symlink?(root)
        expanded_root = File.realpath(root)
        next unless File.dirname(File.expand_path(path)) == expanded_root
        File.unlink(path) if File.file?(path)
      rescue Errno::ENOENT
        nil
      end
    end

    def slack_payload(repository:, version:, track:, result:, run_url:, source_url:)
      JSON.generate(
        "repository" => repository.to_s,
        "version" => version.to_s,
        "track" => track.to_s,
        "result" => result.to_s,
        "run_url" => run_url.to_s,
        "source_url" => source_url.to_s
      )
    end

    def doctor(env:, target:, context:, actions:, project_root:)
      steps = distribution_steps(target: target, firebase_enabled: env["ENABLE_FIREBASE_APP_DISTRIBUTION"])
      deploy = context.to_s == "deploy"
      report = []
      ruby_version = actions.respond_to?(:runtime_ruby_version) ? actions.runtime_ruby_version : RUBY_VERSION
      ruby_ready = supported_ruby_version?(ruby_version)
      report << doctor_entry(ruby_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
        ruby_ready ? "Ruby #{ruby_version} satisfies >= 3.2 and < 4.0" : "Ruby >= 3.2 and < 4.0 is required")
      flutter_ready = actions.respond_to?(:tool_available?) && actions.tool_available?("flutter")
      report << doctor_entry(flutter_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
        flutter_ready ? "Flutter is available" : "Flutter is not available on PATH")
      files_ready = generated_fastlane_files_ready?(project_root)
      report << doctor_entry(files_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
        files_ready ? "Pinned Fastlane files are present" : "Pinned Fastlane files are incomplete")
      build_runner = pubspec_has_build_runner?(project_root)
      report << doctor_entry("PASS", build_runner ? "build_runner is configured" : "build_runner is not configured")
      report << doctor_entry("PASS", "APP_PACKAGE_NAME is configured") unless blank?(env["APP_PACKAGE_NAME"])
      report << doctor_entry(deploy ? "FAIL" : "WARN", "APP_PACKAGE_NAME is not configured") if blank?(env["APP_PACKAGE_NAME"])

      signing_ready = signing_inputs_complete?(env) || local_key_properties_complete?(project_root)
      report << doctor_entry(signing_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
        signing_ready ? "Android release signing input is available" : "Android release signing input is incomplete")

      if steps.include?("play-store")
        track = env.fetch("PLAY_STORE_TRACK", "internal").to_s
        track_ready = track.match?(/\A[A-Za-z0-9._-]+\z/)
        report << doctor_entry(track_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
          track_ready ? "Play track is configured" : "Play track contains unsupported characters")
        play_ready = credential_input_present?(env, "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", project_root,
          "android/fastlane/google-play-service-account.json")
        report << doctor_entry(play_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
          play_ready ? "Google Play credentials are configured" : "Google Play credentials are not configured")
      end
      if steps.include?("firebase")
        firebase_ready = !blank?(env["FIREBASE_APP_ID"]) &&
          credential_input_present?(env, "FIREBASE_SERVICE_ACCOUNT_JSON", project_root,
            "android/fastlane/firebase-service-account.json")
        report << doctor_entry(firebase_ready ? "PASS" : (deploy ? "FAIL" : "WARN"),
          firebase_ready ? "Firebase credentials are configured" : "Firebase credentials are not configured")
      end

      report.each { |entry| actions.log(entry[:level].downcase.to_sym, "#{entry[:level]}: #{entry[:message]}") if actions.respond_to?(:log) }
      if deploy && report.any? { |entry| entry[:level] == "FAIL" }
        raise PreflightError, "deploy preflight failed before any network action"
      end
      report
    end

    def release(options:, env:, actions:, project_root:)
      options = symbolize_keys(options || {})
      environment = stringify_keys(env || {})
      root = canonical_directory(project_root, "project root")
      explicit_target = options[:distribution_target] || environment["DISTRIBUTION_TARGET"]
      steps = distribution_steps(
        target: explicit_target,
        firebase_enabled: environment["ENABLE_FIREBASE_APP_DISTRIBUTION"]
      )
      target = steps == %w[play-store firebase] ? "both" : steps.first
      artifact_type = release_artifact_type(steps, environment)
      validate_release_policy!(steps, environment, artifact_type)
      doctor(env: environment, target: target, context: "deploy", actions: actions, project_root: root)

      records = []
      temp_root = Dir.mktmpdir("flutter-play-store-release-")
      File.chmod(0o700, temp_root)
      result = nil
      successful = []
      failed_destination = nil
      original_error = nil

      begin
        credentials = prepare_credentials(
          steps: steps, env: environment, project_root: root,
          temp_root: temp_root, records: records
        )
        signing_environment = prepare_signing(
          env: environment, project_root: root, temp_root: temp_root,
          records: records
        )

        actions.prepare(run_tests: truthy?(environment.fetch("RUN_FLUTTER_TESTS", "true")))
        pubspec_name, pubspec_code = read_pubspec_version(root)
        exact_tags = if blank?(options[:version_name]) && blank?(environment["VERSION_NAME"])
          actions.exact_head_tags
        else
          []
        end
        version_name = resolve_version_name(
          option: options[:version_name], env: environment["VERSION_NAME"],
          exact_head_tags: exact_tags, pubspec: pubspec_name
        )

        flavor = present(options[:flavor] || environment["FLUTTER_FLAVOR"])
        target_file = present(options[:target] || environment["RELEASE_DART_TARGET"]) || "lib/main.dart"
        release_id = actions.release_application_id(flavor: flavor)
        validate_package_name!(environment.fetch("APP_PACKAGE_NAME"), release_id)
        validate_firebase_mapping!(environment, actions) if steps.include?("firebase")
        version_code = if steps.include?("play-store")
          resolve_play_version_code(steps: steps, env: environment, actions: actions,
            json_key: credentials.fetch(:play).fetch(:path), package_name: environment.fetch("APP_PACKAGE_NAME"))
        else
          resolve_local_version_code(environment, pubspec_code, actions)
        end

        artifact_path = build_once(
          project_root: root, artifact_type: artifact_type, version_name: version_name,
          version_code: version_code, flavor: flavor, target: target_file,
          environment: signing_environment, actions: actions
        )

        if steps.include?("play-store")
          begin
            upload_play_store(
              env: environment, actions: actions, credential: credentials.fetch(:play),
              artifact_path: artifact_path, version_name: version_name
            )
            successful << "play-store"
          rescue StandardError => error
            failed_destination = "play-store"
            raise error
          end
        end

        if steps.include?("firebase")
          begin
            upload_firebase(
              env: environment, actions: actions, credential: credentials.fetch(:firebase),
              artifact_path: artifact_path, artifact_type: artifact_type,
              version_name: version_name, version_code: version_code
            )
            successful << "firebase"
          rescue StandardError => error
            failed_destination = "firebase"
            raise error
          end
        end

        result = result_payload(
          status: "SUCCESS", target: target, version: version_name,
          track: environment.fetch("PLAY_STORE_TRACK", "internal"),
          artifact_type: artifact_type, artifact_path: artifact_path,
          successful: successful, failed_destination: nil,
          message: "Release completed successfully."
        )
        write_result_if_requested(environment, result, actions)
        log_result(actions, result)
        notify_if_requested(environment, actions, result)
        result
      rescue StandardError => error
        original_error = error
        partial = successful.include?("play-store") && failed_destination == "firebase"
        status = partial ? "PARTIAL_SUCCESS" : "FAILURE"
        message = partial ?
          "Play upload succeeded, but Firebase distribution failed; Play was not rolled back." :
          "Release failed before all requested destinations completed."
        result ||= result_payload(
          status: status, target: target,
          version: defined?(version_name) && version_name ? version_name : nil,
          track: environment.fetch("PLAY_STORE_TRACK", "internal"),
          artifact_type: artifact_type,
          artifact_path: defined?(artifact_path) && artifact_path ? artifact_path : nil,
          successful: successful, failed_destination: failed_destination,
          message: message
        )
        write_result_if_requested(environment, result, actions, preserve: original_error)
        log_result(actions, result)
        notify_if_requested(environment, actions, result)
        if partial
          raise PartialSuccessError, "PARTIAL_SUCCESS: #{message}"
        end
        raise original_error
      ensure
        cleanup_owned_secrets(records)
        FileUtils.remove_entry_secure(temp_root) if temp_root && File.directory?(temp_root)
      end
    end

    def prepare_only(env:, actions:)
      actions.prepare(run_tests: truthy?(stringify_keys(env)["RUN_FLUTTER_TESTS"] || "true"))
    end

    def build_only(options:, env:, actions:, project_root:)
      options = symbolize_keys(options || {})
      environment = stringify_keys(env || {})
      root = canonical_directory(project_root, "project root")
      doctor(env: environment, target: "play-store", context: "build", actions: actions, project_root: root)
      records = []
      temp_root = Dir.mktmpdir("flutter-play-store-build-")
      File.chmod(0o700, temp_root)
      begin
        signing_environment = prepare_signing(env: environment, project_root: root,
          temp_root: temp_root, records: records)
        actions.prepare(run_tests: truthy?(environment.fetch("RUN_FLUTTER_TESTS", "true")))
        pubspec_name, pubspec_code = read_pubspec_version(root)
        exact_tags = if blank?(options[:version_name]) && blank?(environment["VERSION_NAME"])
          actions.exact_head_tags
        else
          []
        end
        version_name = resolve_version_name(option: options[:version_name], env: environment["VERSION_NAME"],
          exact_head_tags: exact_tags, pubspec: pubspec_name)
        version_code = resolve_local_version_code(environment, pubspec_code, actions)
        build_once(project_root: root, artifact_type: "AAB", version_name: version_name,
          version_code: version_code, flavor: present(options[:flavor] || environment["FLUTTER_FLAVOR"]),
          target: present(options[:target] || environment["RELEASE_DART_TARGET"]) || "lib/main.dart",
          environment: signing_environment, actions: actions)
      ensure
        cleanup_owned_secrets(records)
        FileUtils.remove_entry_secure(temp_root) if temp_root && File.directory?(temp_root)
      end
    end

    def execute_fastlane_lane(lane, options, dsl)
      adapter = FastlaneAdapter.new(dsl)
      project_root = adapter.project_root
      case lane.to_sym
      when :doctor
        doctor(env: ENV.to_h, target: ENV["DISTRIBUTION_TARGET"], context: "doctor",
          actions: adapter, project_root: project_root)
      when :prepare
        prepare_only(env: ENV.to_h, actions: adapter)
      when :build
        build_only(options: options, env: ENV.to_h, actions: adapter, project_root: project_root)
      when :release
        release(options: options, env: ENV.to_h, actions: adapter, project_root: project_root)
      else
        raise ConfigurationError, "unknown Fastlane lane: #{lane}"
      end
    rescue ReleaseError => error
      adapter.fail!(error.message)
    end

    def handle_fastlane_error(lane, exception, _options = nil)
      classification = if exception.is_a?(PartialSuccessError) || exception.message.to_s.start_with?("PARTIAL_SUCCESS:")
        "PARTIAL_SUCCESS"
      else
        "FAILURE"
      end
      message = "#{classification}: Android lane #{lane} terminated"
      if defined?(FastlaneCore::UI)
        FastlaneCore::UI.error(message)
      else
        warn(message)
      end
    end

    private

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def present(value)
      blank?(value) ? nil : value.to_s.strip
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    def ordered_unique(values)
      values.each_with_object([]) { |value, result| result << value unless result.include?(value) }
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
    end

    def canonical_directory(path, label)
      expanded = File.expand_path(path.to_s)
      unless File.directory?(expanded) && !File.symlink?(expanded)
        raise ConfigurationError, "#{label} is not a safe directory"
      end
      File.realpath(expanded)
    end

    def ensure_private_directory!(path)
      mode = File.stat(path).mode & 0o777
      raise ConfigurationError, "owned secret root must use mode 0700" unless mode == 0o700
    end

    def canonical_secret_file(path, label)
      expanded = File.expand_path(path.to_s)
      unless safe_regular_file?(expanded) && File.size(expanded).positive?
        raise ConfigurationError, "#{label} path must name a nonempty regular file"
      end
      File.realpath(expanded)
    end

    def safe_regular_file?(path)
      File.file?(path) && !File.symlink?(path)
    rescue Errno::ENOENT, Errno::ENOTDIR
      false
    end

    def safe_label(label)
      value = label.to_s.downcase.gsub(/[^a-z0-9]+/, "-").sub(/\A-+/, "").sub(/-+\z/, "")
      value.empty? ? "secret" : value
    end

    def append_java_unicode_escape(output, codepoint)
      if codepoint <= 0xffff
        output << format("\\u%04x", codepoint)
      else
        scalar = codepoint - 0x10000
        output << format("\\u%04x\\u%04x", 0xd800 + (scalar >> 10), 0xdc00 + (scalar & 0x3ff))
      end
    end

    def normalize_artifact_type(value)
      type = value.to_s.upcase
      raise ConfigurationError, "artifact type must be AAB or APK" unless %w[AAB APK].include?(type)
      type
    end

    def doctor_entry(level, message)
      { level: level, message: message }
    end

    def credential_input_present?(env, prefix, project_root, default_relative)
      !blank?(env["#{prefix}_PATH"]) || !blank?(env["#{prefix}_BASE64"]) ||
        safe_regular_file?(File.join(project_root, default_relative))
    end

    def signing_inputs_complete?(env)
      keystore = !blank?(env["ANDROID_KEYSTORE_PATH"]) || !blank?(env["ANDROID_KEYSTORE_BASE64"])
      keystore && %w[ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD].all? do |name|
        !blank?(env[name])
      end
    end

    def supported_ruby_version?(value)
      version = Gem::Version.new(value.to_s)
      version >= Gem::Version.new("3.2") && version < Gem::Version.new("4.0")
    rescue ArgumentError
      false
    end

    def generated_fastlane_files_ready?(project_root)
      required = %w[
        android/Gemfile
        android/Gemfile.lock
        android/fastlane/Fastfile
        android/fastlane/Pluginfile
        android/fastlane/lib/flutter_play_store_release.rb
      ]
      return false unless required.all? { |relative| safe_regular_file?(File.join(project_root, relative)) }
      gemfile = File.read(File.join(project_root, "android", "Gemfile"))
      plugin = File.read(File.join(project_root, "android", "fastlane", "Pluginfile"))
      lock = File.read(File.join(project_root, "android", "Gemfile.lock"))
      gemfile.include?('gem "fastlane", "= 2.237.0"') &&
        plugin.include?('gem "fastlane-plugin-firebase_app_distribution", "= 1.0.0"') &&
        lock.include?("fastlane (2.237.0)") && lock.include?("fastlane-plugin-firebase_app_distribution (1.0.0)")
    rescue Errno::EACCES
      false
    end

    def pubspec_has_build_runner?(project_root)
      path = File.join(project_root, "pubspec.yaml")
      safe_regular_file?(path) && File.read(path).match?(/^\s*build_runner:\s/m)
    rescue Errno::EACCES
      false
    end

    def local_key_properties_complete?(project_root)
      path = File.join(File.expand_path(project_root.to_s), "android", "key.properties")
      return false unless safe_regular_file?(path)
      keys = File.readlines(path, chomp: true).each_with_object({}) do |line, result|
        next if line.strip.empty? || line.lstrip.start_with?("#")
        key, value = line.split("=", 2)
        result[key.to_s.strip] = value.to_s unless key.nil?
      end
      return false unless %w[storeFile storePassword keyAlias keyPassword].all? { |key| !blank?(keys[key]) }
      store_file = java_properties_unescape(keys.fetch("storeFile"))
      keystore = if store_file.start_with?(File::SEPARATOR)
        store_file
      else
        File.expand_path(store_file, File.join(project_root, "android", "app"))
      end
      safe_regular_file?(keystore) && File.size(keystore).positive?
    rescue Errno::EACCES, ConfigurationError
      false
    end

    def java_properties_unescape(value)
      input = value.to_s
      output = +""
      index = 0
      while index < input.length
        character = input[index]
        unless character == "\\"
          output << character
          index += 1
          next
        end
        index += 1
        raise ConfigurationError, "invalid Java properties escape" if index >= input.length
        escaped = input[index]
        if escaped == "u"
          hex = input[(index + 1), 4]
          raise ConfigurationError, "invalid Java properties Unicode escape" unless hex && hex.match?(/\A[0-9A-Fa-f]{4}\z/)
          output << Integer(hex, 16).chr(Encoding::UTF_8)
          index += 5
        else
          output << ({ "t" => "\t", "n" => "\n", "r" => "\r", "f" => "\f" }.fetch(escaped, escaped))
          index += 1
        end
      end
      output
    end

    def release_artifact_type(steps, env)
      return "AAB" if steps == ["play-store"]
      requested = normalize_artifact_type(env.fetch("FIREBASE_ANDROID_ARTIFACT_TYPE", "AAB"))
      if steps.include?("play-store") && requested != "AAB"
        raise ConfigurationError, "both requires AAB so the Play artifact can be reused without rebuilding"
      end
      requested
    end

    def validate_release_policy!(steps, env, artifact_type)
      if steps.include?("play-store")
        status = env.fetch("PLAY_STORE_RELEASE_STATUS", "completed")
        unless %w[completed draft inProgress].include?(status)
          if status == "halted"
            raise ConfigurationError, "halted mutates an existing rollout and is outside this new-binary lane"
          end
          raise ConfigurationError, "release status must be completed, draft, or inProgress"
        end
        if status == "inProgress"
          begin
            rollout = Float(env["PLAY_STORE_ROLLOUT"])
          rescue ArgumentError, TypeError
            raise ConfigurationError, "inProgress requires PLAY_STORE_ROLLOUT strictly between 0 and 1"
          end
          unless rollout > 0.0 && rollout < 1.0
            raise ConfigurationError, "inProgress requires PLAY_STORE_ROLLOUT strictly between 0 and 1"
          end
        end
      end
      if steps.include?("play-store") && env.fetch("PLAY_STORE_TRACK", "internal") == "production" &&
          !truthy?(env["CONFIRM_PRODUCTION_DEPLOY"])
        raise ConfigurationError, "production requires CONFIRM_PRODUCTION_DEPLOY=true"
      end
      if steps.include?("firebase") && artifact_type == "AAB" &&
          !truthy?(env["CONFIRM_FIREBASE_AAB_PLAY_LINKED"])
        raise ConfigurationError,
          "Firebase AAB distribution requires CONFIRM_FIREBASE_AAB_PLAY_LINKED=true after link and certificate review"
      end
    end

    def prepare_credentials(steps:, env:, project_root:, temp_root:, records:)
      credentials = {}
      if steps.include?("play-store")
        record = resolve_secret(
          path_value: env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"],
          base64_value: env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64"],
          default_path: File.join(project_root, "android", "fastlane", "google-play-service-account.json"),
          label: "Google Play service account", temp_root: temp_root
        )
        validate_service_account_json!(record[:path], "Google Play service account")
        records << record
        credentials[:play] = record
      end
      if steps.include?("firebase")
        raise ConfigurationError, "FIREBASE_APP_ID is required" if blank?(env["FIREBASE_APP_ID"])
        record = resolve_secret(
          path_value: env["FIREBASE_SERVICE_ACCOUNT_JSON_PATH"],
          base64_value: env["FIREBASE_SERVICE_ACCOUNT_JSON_BASE64"],
          default_path: File.join(project_root, "android", "fastlane", "firebase-service-account.json"),
          label: "Firebase service account", temp_root: temp_root
        )
        validate_service_account_json!(record[:path], "Firebase service account")
        records << record
        credentials[:firebase] = record
      end
      credentials
    end

    def validate_service_account_json!(path, label)
      document = JSON.parse(File.binread(path))
      valid = document.is_a?(Hash) && document["type"] == "service_account" &&
        !blank?(document["client_email"]) && !blank?(document["private_key"])
      raise ConfigurationError, "#{label} JSON is not a complete service-account document" unless valid
    rescue JSON::ParserError
      raise ConfigurationError, "#{label} JSON is invalid"
    end

    def prepare_signing(env:, project_root:, temp_root:, records:)
      workspace = File.join(project_root, "android", "key.properties")
      ci = truthy?(env["CI"]) || truthy?(env["GITHUB_ACTIONS"])
      if ci && (File.exist?(workspace) || File.symlink?(workspace))
        raise ConfigurationError, "CI refuses a workspace android/key.properties; use the temporary override"
      end

      input_names = %w[ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD]
      any_input = input_names.any? { |name| !blank?(env[name]) }
      unless any_input
        if !ci && local_key_properties_complete?(project_root)
          return {}
        end
        raise ConfigurationError, "complete Android signing inputs are required"
      end
      unless signing_inputs_complete?(env)
        raise ConfigurationError, "Android signing environment inputs are incomplete"
      end

      keystore = resolve_secret(
        path_value: env["ANDROID_KEYSTORE_PATH"], base64_value: env["ANDROID_KEYSTORE_BASE64"],
        default_path: nil, label: "Android keystore", temp_root: temp_root
      )
      records << keystore
      properties_path = File.join(temp_root, "android-key-#{SecureRandom.hex(10)}.properties")
      write_key_properties(
        path: properties_path, keystore_path: keystore[:path],
        store_password: env["ANDROID_KEYSTORE_PASSWORD"], key_alias: env["ANDROID_KEY_ALIAS"],
        key_password: env["ANDROID_KEY_PASSWORD"]
      )
      properties_record = { path: properties_path, owned: true, label: "Android key properties", root: temp_root }
      records << properties_record
      { "ANDROID_KEY_PROPERTIES_PATH" => properties_path }
    end

    def read_pubspec_version(project_root)
      path = File.join(project_root, "pubspec.yaml")
      raise ConfigurationError, "pubspec.yaml is missing" unless safe_regular_file?(path)
      raw = nil
      File.foreach(path) do |line|
        match = line.match(/^version:\s*['\"]?([^'\"\s#]+)['\"]?\s*(?:#.*)?$/)
        if match
          raw = match[1]
          break
        end
      end
      raise ConfigurationError, "pubspec.yaml has no static version" if blank?(raw)
      name, code = raw.split("+", 2)
      [name, code]
    end

    def resolve_play_version_code(steps:, env:, actions:, json_key:, package_name:)
      selected = env.fetch("PLAY_STORE_TRACK", "internal").to_s.strip
      configured = env.fetch("PLAY_STORE_VERSION_TRACKS", DEFAULT_PLAY_TRACKS.join(","))
        .split(",").map(&:strip).reject(&:empty?)
      tracks = ordered_unique([selected] + configured)
      next_active_track_code(
        track_names: tracks,
        fetch_track_codes: lambda do |track|
          actions.google_play_track_version_codes(
            json_key: json_key, package_name: package_name, track: track
          )
        end
      )
    end

    def resolve_local_version_code(env, pubspec_code, actions)
      return validate_version_code(env["VERSION_CODE"], source: "VERSION_CODE") unless blank?(env["VERSION_CODE"])
      return validate_version_code(pubspec_code, source: "pubspec build number") unless blank?(pubspec_code)
      validate_version_code(actions.git_commit_count, source: "Git commit count")
    end

    def validate_package_name!(configured, detected)
      if blank?(detected)
        raise ConfigurationError, "could not resolve the selected release applicationId"
      end
      return if configured.to_s == detected.to_s
      raise ConfigurationError, "APP_PACKAGE_NAME does not match the selected release applicationId"
    end

    def validate_firebase_mapping!(env, actions)
      mappings = Array(actions.firebase_clients)
      if mappings.empty?
        unless truthy?(env["CONFIRM_FIREBASE_PACKAGE_MATCH"])
          raise ConfigurationError,
            "google-services.json mapping evidence is absent; require CONFIRM_FIREBASE_PACKAGE_MATCH=true"
        end
        return
      end
      package_name = env.fetch("APP_PACKAGE_NAME")
      app_id = env.fetch("FIREBASE_APP_ID")
      matched = mappings.any? do |mapping|
        values = symbolize_keys(mapping)
        values[:package_name].to_s == package_name && values[:app_id].to_s == app_id
      end
      return if matched
      raise ConfigurationError,
        "detected google-services.json package/app-ID mapping does not match the selected release"
    end

    def build_once(project_root:, artifact_type:, version_name:, version_code:, flavor:, target:, environment:, actions:)
      type = normalize_artifact_type(artifact_type)
      output_root = File.join(project_root, "build", "app", "outputs")
      pattern = type == "AAB" ? "bundle/**/*.aab" : "apk/**/*.apk"
      existing = Dir.glob(File.join(output_root, pattern)).select { |path| safe_regular_file?(path) }
      if flavor
        existing.select! { |path| path.downcase.include?(flavor.downcase) }
      end
      untouched = Dir.glob(File.join(output_root, pattern)).map { |path| File.expand_path(path) } -
        existing.map { |path| File.expand_path(path) }
      quarantine = Dir.mktmpdir("artifact-quarantine-", File.dirname(project_root))
      moved = []
      accepted = false
      begin
        existing.each_with_index do |path, index|
          destination = File.join(quarantine, index.to_s)
          File.rename(path, destination)
          moved << [path, destination]
        end
        started_at = Time.now - 2
        actions.flutter_build(
          artifact_type: type, build_name: version_name, build_number: version_code,
          flavor: flavor, target: target, environment: environment
        )
        artifact = locate_fresh_artifact(
          project_root: project_root, build_started_at: started_at,
          prior_outputs: [], flavor: flavor, artifact_type: type
        )
        accepted = true
        FileUtils.remove_entry_secure(quarantine)
        quarantine = nil
        artifact
      rescue Exception # rubocop:disable Lint/RescueException -- rollback must run for signals too
        unless accepted
          Dir.glob(File.join(output_root, pattern)).each do |path|
            next if untouched.include?(File.expand_path(path))
            File.unlink(path) if safe_regular_file?(path)
          rescue Errno::ENOENT
            nil
          end
          moved.reverse_each do |original, stored|
            next unless safe_regular_file?(stored)
            FileUtils.mkdir_p(File.dirname(original))
            File.rename(stored, original)
          end
        end
        raise
      ensure
        FileUtils.remove_entry_secure(quarantine) if quarantine && File.directory?(quarantine)
      end
    end

    def upload_play_store(env:, actions:, credential:, artifact_path:, version_name:)
      status = env.fetch("PLAY_STORE_RELEASE_STATUS", "completed")
      options = {
        json_key: credential.fetch(:path),
        aab: artifact_path,
        package_name: env.fetch("APP_PACKAGE_NAME"),
        track: env.fetch("PLAY_STORE_TRACK", "internal"),
        release_status: status,
        version_name: version_name,
        skip_upload_metadata: true,
        skip_upload_changelogs: true,
        skip_upload_images: true,
        skip_upload_screenshots: true
      }
      options[:rollout] = Float(env.fetch("PLAY_STORE_ROLLOUT")) if status == "inProgress"
      actions.upload_to_play_store(**options)
    rescue ReleaseError
      raise
    rescue StandardError => error
      raise ExternalActionError, "Google Play binary upload failed: #{classify_play_failure(error)}"
    end

    def classify_play_failure(error)
      text = error.message.to_s.downcase
      if text.match?(/permission|unauthori[sz]ed|forbidden|credential|authentication|\b401\b|\b403\b/)
        "authentication or permission was rejected; verify the service account and Play Console access"
      elsif text.match?(/first release|first upload|draft app|not published|no app with given|application.*not found/)
        "the app requires first-release/manual bootstrap in Play Console; follow the first-release checklist"
      elsif text.match?(/version code.*already|already been used|version.*reuse/)
        "the active-track version code was rejected as reused; refresh every configured track and retry the serialized upload"
      else
        "the Play action failed (#{error.class})"
      end
    end

    def upload_firebase(env:, actions:, credential:, artifact_path:, artifact_type:, version_name:, version_code:)
      notes = present(env["FIREBASE_RELEASE_NOTES"]) || "Version #{version_name} (#{version_code})"
      actions.firebase_app_distribution(
        app: env.fetch("FIREBASE_APP_ID"),
        android_artifact_type: artifact_type,
        android_artifact_path: artifact_path,
        service_credentials_file: credential.fetch(:path),
        release_notes: notes,
        testers: present(env["FIREBASE_TESTERS"]),
        groups: present(env["FIREBASE_TESTER_GROUPS"])
      )
    rescue ReleaseError
      raise
    rescue StandardError => error
      raise ExternalActionError, "Firebase distribution failed: #{error.class}"
    end

    def result_payload(status:, target:, version:, track:, artifact_type:, artifact_path:, successful:, failed_destination:, message:)
      {
        "schema_version" => RESULT_SCHEMA_VERSION,
        "status" => status,
        "target" => target,
        "version" => version,
        "track" => track,
        "artifact_type" => artifact_type,
        "artifact_path" => artifact_path,
        "successful_destinations" => successful.dup,
        "failed_destination" => failed_destination,
        "message" => message
      }
    end

    def write_result_if_requested(env, result, actions, preserve: nil)
      path = present(env["RELEASE_RESULT_PATH"])
      return if path.nil?
      destination = File.expand_path(path)
      FileUtils.mkdir_p(File.dirname(destination))
      temp = Tempfile.new([".release-result-", ".json"], File.dirname(destination), mode: 0o600)
      begin
        temp.write(JSON.generate(result))
        temp.write("\n")
        temp.flush
        temp.fsync
        temp.close
        File.rename(temp.path, destination)
        File.chmod(0o600, destination)
      ensure
        temp.close! rescue nil
      end
    rescue StandardError => error
      actions.log(:warn, "WARN: could not write the nonsecret release result (#{error.class})") if actions.respond_to?(:log)
      raise error unless preserve
    end

    def log_result(actions, result)
      fields = %w[status target version track artifact_type artifact_path successful_destinations failed_destination message]
      fields.each do |field|
        actions.log(:info, "#{field}=#{result[field].is_a?(Array) ? result[field].join(",") : result[field]}") if actions.respond_to?(:log)
      end
    end

    def notify_if_requested(env, actions, result)
      return if env["SLACK_NOTIFICATION_OWNER"].to_s == "github-actions"
      webhook = present(env["SLACK_WEBHOOK_URL"])
      return unless webhook
      notify = result["status"] == "SUCCESS" ? truthy?(env["SLACK_NOTIFY_SUCCESS"]) : truthy?(env["SLACK_NOTIFY_FAILURE"])
      return unless notify
      payload = slack_payload(
        repository: env["GITHUB_REPOSITORY"], version: result["version"], track: result["track"],
        result: result["status"], run_url: run_url(env), source_url: source_url(env)
      )
      actions.notify_slack(webhook: webhook, payload: payload)
    rescue StandardError => error
      actions.log(:warn, "WARN: Slack notification failed without changing the release result (#{error.class})") if actions.respond_to?(:log)
    end

    def run_url(env)
      return env["RUN_URL"] unless blank?(env["RUN_URL"])
      return "" if blank?(env["GITHUB_SERVER_URL"]) || blank?(env["GITHUB_REPOSITORY"]) || blank?(env["GITHUB_RUN_ID"])
      "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}/actions/runs/#{env["GITHUB_RUN_ID"]}"
    end

    def source_url(env)
      return env["SOURCE_URL"] unless blank?(env["SOURCE_URL"])
      return "" if blank?(env["GITHUB_SERVER_URL"]) || blank?(env["GITHUB_REPOSITORY"]) || blank?(env["GITHUB_SHA"])
      "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}/commit/#{env["GITHUB_SHA"]}"
    end
  end

  # The only object allowed to invoke Fastlane actions. Keeping this adapter
  # narrow makes all network-facing calls mockable in pure Minitest.
  class FastlaneAdapter
    attr_reader :project_root

    def initialize(dsl, project_root: nil, command_runner: nil)
      @dsl = dsl
      @project_root = project_root || File.expand_path("../../..", __dir__)
      @command_runner = command_runner
    end

    def exact_head_tags
      output = @dsl.sh("git", "tag", "--points-at", "HEAD", log: false)
      output.to_s.lines.map(&:strip).reject(&:empty?)
    end

    def runtime_ruby_version
      RUBY_VERSION
    end

    def tool_available?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        path = File.join(directory, name.to_s)
        File.file?(path) && File.executable?(path)
      end
    end

    def git_commit_count
      @dsl.sh("git", "rev-list", "--count", "HEAD", log: false).to_s.strip
    end

    def prepare(run_tests:)
      @dsl.sh("flutter", "pub", "get")
      pubspec = File.join(@project_root, "pubspec.yaml")
      if File.file?(pubspec) && File.read(pubspec).match?(/^\s*build_runner:\s/m)
        @dsl.sh("flutter", "pub", "run", "build_runner", "build", "--delete-conflicting-outputs")
      end
      @dsl.sh("flutter", "analyze") unless ENV["RUN_FLUTTER_ANALYZE"].to_s.downcase == "false"
      @dsl.sh("flutter", "test") if run_tests
    end

    def flutter_build(artifact_type:, build_name:, build_number:, flavor:, target:, environment:)
      command = ["flutter", "build", artifact_type == "AAB" ? "appbundle" : "apk", "--release",
        "--build-name", build_name.to_s, "--build-number", build_number.to_s, "--target", target.to_s]
      command.concat(["--flavor", flavor.to_s]) if flavor
      @dsl.sh(environment, *command)
    end

    def release_application_id(flavor:)
      FlutterPlayStoreRelease.send(:read_release_application_id, @project_root, flavor)
    end

    def firebase_clients
      FlutterPlayStoreRelease.send(:read_firebase_clients, @project_root)
    end

    def google_play_track_version_codes(**options)
      @dsl.google_play_track_version_codes(**options)
    end

    def upload_to_play_store(**options)
      @dsl.upload_to_play_store(**options)
    end

    def firebase_app_distribution(**options)
      @dsl.firebase_app_distribution(**options)
    end

    def notify_slack(webhook:, payload:)
      config = Tempfile.new("fprs-curl-config")
      File.chmod(0o600, config.path)
      config.write("url = #{JSON.generate(webhook)}\n")
      config.flush
      command = ["curl", "--silent", "--show-error", "--fail-with-body", "--config", config.path,
        "--header", "Content-Type: application/json", "--data-binary", "@-"]
      _stdout, _stderr, status = if @command_runner
        @command_runner.call(command, payload)
      else
        Open3.capture3(*command, stdin_data: payload)
      end
      raise ExternalActionError, "Slack webhook request failed" unless status.success?
      true
    ensure
      config.close! if config
    end

    def log(level, message)
      if defined?(FastlaneCore::UI)
        method = level.to_sym == :warn ? :important : (level.to_sym == :error ? :error : :message)
        FastlaneCore::UI.public_send(method, message)
      else
        $stderr.puts(message)
      end
    end

    def fail!(message)
      if defined?(FastlaneCore::UI)
        FastlaneCore::UI.user_error!(message)
      end
      raise ReleaseError, message
    end
  end

  class << self
    private

    def read_release_application_id(project_root, flavor)
      candidates = %w[android/app/build.gradle.kts android/app/build.gradle].map { |path| File.join(project_root, path) }
      path = candidates.find { |candidate| safe_regular_file?(candidate) }
      return nil unless path
      text = File.read(path)
      base = text[/\bapplicationId\s*(?:=\s*)?["']([^"']+)["']/, 1]
      identifier = base
      unless blank?(flavor)
        block = find_gradle_named_block(text, flavor.to_s)
        if block
          explicit = block[/\bapplicationId\s*(?:=\s*)?["']([^"']+)["']/, 1]
          identifier = explicit if explicit
          suffix = block[/\bapplicationIdSuffix\s*(?:=\s*)?["']([^"']+)["']/, 1]
          identifier = "#{identifier}#{suffix}" if suffix && identifier
        end
      end
      release_block = find_gradle_named_block(text, "release")
      if release_block
        release_suffix = release_block[/\bapplicationIdSuffix\s*(?:=\s*)?["']([^"']+)["']/, 1]
        identifier = "#{identifier}#{release_suffix}" if release_suffix && identifier
      end
      identifier
    end

    def find_gradle_named_block(text, name)
      escaped = Regexp.escape(name)
      patterns = [
        /\b#{escaped}\s*\{/m,
        /\b(?:create|maybeCreate|getByName|named)\s*\(\s*["']#{escaped}["']\s*\)\s*\{/m
      ]
      matches = patterns.map { |pattern| pattern.match(text) }.compact
      match = matches.min_by { |candidate| candidate.begin(0) }
      return nil unless match
      opening = text.index("{", match.begin(0))
      extract_gradle_block(text, opening)
    end

    def extract_gradle_block(text, opening)
      return nil unless opening
      depth = 0
      quote = nil
      escaped = false
      line_comment = false
      block_comment = false
      index = opening
      while index < text.length
        character = text[index]
        following = text[index + 1]
        if line_comment
          line_comment = false if character == "\n"
        elsif block_comment
          if character == "*" && following == "/"
            block_comment = false
            index += 1
          end
        elsif quote
          if escaped
            escaped = false
          elsif character == "\\"
            escaped = true
          elsif character == quote
            quote = nil
          end
        elsif character == "/" && following == "/"
          line_comment = true
          index += 1
        elsif character == "/" && following == "*"
          block_comment = true
          index += 1
        elsif character == '"' || character == "'"
          quote = character
        elsif character == "{"
          depth += 1
        elsif character == "}"
          depth -= 1
          return text[(opening + 1)...index] if depth.zero?
        end
        index += 1
      end
      nil
    end

    def read_firebase_clients(project_root)
      paths = Dir.glob(File.join(project_root, "**", "google-services.json"))
      mappings = []
      paths.each do |path|
        next unless safe_regular_file?(path)
        document = JSON.parse(File.read(path))
        Array(document["client"]).each do |client|
          app_id = client.dig("client_info", "mobilesdk_app_id")
          package_name = client.dig("client_info", "android_client_info", "package_name")
          mappings << { package_name: package_name, app_id: app_id } if package_name && app_id
        end
      rescue JSON::ParserError
        raise ConfigurationError, "google-services.json is invalid"
      end
      mappings
    end
  end
end
