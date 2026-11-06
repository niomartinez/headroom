#!/usr/bin/env ruby
# Checks Headroom's App Store listing before it's uploaded, without contacting Apple:
# App Store Connect's length limits, no third-party trademarks where Apple doesn't allow them,
# the URLs, categories, age rating and the screenshots' size and format.
#
#   ruby scripts/release/check-metadata.rb [repository root]
#   ruby scripts/release/check-metadata.rb --self-test
#
# Exits 1 and lists every problem when something is off. Runs on macOS's own Ruby.

require "json"
require "fileutils"
require "tmpdir"

module MetadataCheck
  # App Store Connect's limits, in characters.
  LIMITS = {
    "name" => 30,
    "subtitle" => 30,
    "promotional_text" => 170,
    "description" => 4000,
    "keywords" => 100,
    "release_notes" => 4000
  }.freeze
  REQUIRED = (LIMITS.keys + %w[support_url marketing_url privacy_url]).freeze
  URL_PREFIX = "https://headroom.niomartinez.com".freeze
  REVIEW_NOTES_LIMIT = 4000

  # Other companies' names and products, which the name, subtitle, keywords and promotional text
  # must not use (App Review Guidelines 2.3.7, 5.2.1). The description may name what Headroom
  # works with, nominatively.
  TRADEMARKS = %w[
    claude anthropic openai chatgpt gpt codex copilot github cursor gemini windsurf
    apple mac macos iphone ipad xcode
  ].freeze
  NO_TRADEMARKS_IN = %w[name subtitle keywords promotional_text].freeze
  NON_AFFILIATION = /isn't made by, affiliated with or endorsed by Anthropic[^.]*\./.freeze
  # A description that names another company's product must say Headroom isn't affiliated with that company either.
  PRODUCT_OWNERS = { /\bcodex\b/i => "OpenAI", /\bcopilot\b/i => "GitHub" }.freeze

  # Headroom is for AI usage in general, not only coding (1.1 spec §14.7): no "AI coding" anywhere users or App Review
  # read it.
  RETIRED_WORDING = /\bAI[- ]coding\b/i.freeze
  WORDING_CHECKED_IN = %w[name subtitle promotional_text description keywords release_notes].freeze

  CATEGORIES = %w[
    BOOKS BUSINESS DEVELOPER_TOOLS EDUCATION ENTERTAINMENT FINANCE GAMES GRAPHICS_AND_DESIGN
    HEALTH_AND_FITNESS LIFESTYLE MEDICAL MUSIC NEWS PHOTO_AND_VIDEO PRODUCTIVITY REFERENCE
    SOCIAL_NETWORKING SPORTS TRAVEL UTILITIES WEATHER
  ].freeze

  # Mac screenshots Apple accepts: 16:10.
  SCREENSHOT_SIZES = [[1280, 800], [1440, 900], [2560, 1600], [2880, 1800]].freeze

  module_function

  def text(path)
    File.exist?(path) ? File.read(path, encoding: "UTF-8").strip : nil
  end

  def trademarks_in(value)
    words = value.downcase.scan(/[a-z0-9]+/)
    TRADEMARKS.select { |mark| words.include?(mark) }
  end

  # Every problem with the listing under `fastlane` (a fastlane folder), as sentences.
  def problems(fastlane)
    problems = []
    metadata = File.join(fastlane, "metadata")
    locales = Dir[File.join(metadata, "*")].select { |dir| File.directory?(dir) && File.basename(dir) =~ /\A[a-z]{2}(-[A-Z]{2})?\z/ }
    problems << "No locale folders (like en-US) in #{metadata}." if locales.empty?

    locales.each do |locale_dir|
      locale = File.basename(locale_dir)
      REQUIRED.each do |field|
        value = text(File.join(locale_dir, "#{field}.txt"))
        if value.nil? || value.empty?
          problems << "#{locale}/#{field}.txt is missing or empty."
          next
        end
        limit = LIMITS[field]
        if limit && value.length > limit
          problems << "#{locale}/#{field}.txt has #{value.length} characters; the limit is #{limit}."
        end
        if NO_TRADEMARKS_IN.include?(field) && !(marks = trademarks_in(value)).empty?
          problems << "#{locale}/#{field}.txt names #{marks.join(', ')}: no trademarks there."
        end
        if field.end_with?("_url") && !(value == URL_PREFIX || value.start_with?("#{URL_PREFIX}/"))
          problems << "#{locale}/#{field}.txt should be on #{URL_PREFIX}, not #{value}."
        end
      end

      keywords = text(File.join(locale_dir, "keywords.txt")).to_s.split(",").map(&:strip)
      problems << "#{locale}/keywords.txt has an empty keyword (two commas in a row?)." if keywords.any?(&:empty?)
      duplicates = keywords.map(&:downcase).group_by { |k| k }.select { |_, all| all.size > 1 }.keys
      problems << "#{locale}/keywords.txt repeats #{duplicates.join(', ')}." unless duplicates.empty?
      # The name and subtitle are searchable already: a keyword that repeats one of their words
      # (singular or plural) wastes some of the 100 characters.
      title_words = %w[name subtitle].flat_map { |field| text(File.join(locale_dir, "#{field}.txt")).to_s.downcase.scan(/[a-z0-9]+/) }
      stem = ->(word) { word.downcase.sub(/s\z/, "") }
      repeated = keywords.select { |k| title_words.map(&stem).include?(stem.call(k)) }
      unless repeated.empty?
        problems << "#{locale}/keywords.txt repeats #{repeated.join(', ')} from the name or subtitle, which are searchable already."
      end

      description = text(File.join(locale_dir, "description.txt")).to_s
      if (line = description[NON_AFFILIATION])
        PRODUCT_OWNERS.each do |product, owner|
          next unless description =~ product && !line.include?(owner)
          problems << "#{locale}/description.txt names a product of #{owner}, but its non-affiliation line doesn't name #{owner}."
        end
      else
        problems << "#{locale}/description.txt lacks the non-affiliation line."
      end

      WORDING_CHECKED_IN.each do |field|
        next unless text(File.join(locale_dir, "#{field}.txt")).to_s =~ RETIRED_WORDING
        problems << "#{locale}/#{field}.txt says \"#{Regexp.last_match(0)}\": Headroom is about AI usage, not only coding."
      end
    end

    copyright = text(File.join(metadata, "copyright.txt"))
    unless copyright =~ /\A\d{4} \S.*\z/
      problems << "copyright.txt should read like \"2026 Nio Martinez\" (App Store Connect adds the ©)."
    end
    %w[primary_category secondary_category].each do |field|
      value = text(File.join(metadata, "#{field}.txt"))
      problems << "#{field}.txt is #{value.inspect}, not an App Store category." unless CATEGORIES.include?(value)
    end

    notes = text(File.join(metadata, "review_information", "notes.txt"))
    if notes.nil? || notes.empty?
      problems << "review_information/notes.txt is missing."
    else
      problems << "review_information/notes.txt has #{notes.length} characters; the limit is #{REVIEW_NOTES_LIMIT}." if notes.length > REVIEW_NOTES_LIMIT
      problems << "review_information/notes.txt should tell reviewers about Show sample data." unless notes.include?("Show sample data")
      problems << "review_information/notes.txt says \"#{notes[RETIRED_WORDING]}\": Headroom is about AI usage, not only coding." if notes =~ RETIRED_WORDING
    end
    %w[first_name last_name phone_number email_address].each do |field|
      if File.exist?(File.join(metadata, "review_information", "#{field}.txt"))
        problems << "review_information/#{field}.txt is committed; the contact comes from the environment (fastlane/.env.example)."
      end
    end

    problems.concat(rating_problems(File.join(fastlane, "rating_config.json")))
    problems.concat(screenshot_problems(File.join(fastlane, "screenshots")))
    problems
  end

  # A 4+ rating: every content level NONE, every yes/no question no.
  def rating_problems(path)
    return ["rating_config.json is missing."] unless File.exist?(path)
    rating = JSON.parse(File.read(path, encoding: "UTF-8"))
    rating.reject { |_, value| value == "NONE" || value == false }.map do |key, value|
      "rating_config.json sets #{key} to #{value.inspect}; a 4+ rating needs NONE or false."
    end
  rescue JSON::ParserError => error
    ["rating_config.json isn't valid JSON: #{error.message}"]
  end

  def screenshot_problems(dir)
    problems = []
    Dir[File.join(dir, "*")].select { |d| File.directory?(d) }.each do |locale_dir|
      shots = Dir[File.join(locale_dir, "*.png")].sort
      locale = File.basename(locale_dir)
      problems << "screenshots/#{locale} has #{shots.size} screenshots; Mac apps need 1 to 10." unless (1..10).cover?(shots.size)
      shots.each do |shot|
        info = image_info(shot)
        next problems << "Couldn't read #{shot} with sips." unless info
        unless SCREENSHOT_SIZES.include?([info[:width], info[:height]])
          problems << "#{File.basename(shot)} is #{info[:width]}×#{info[:height]}; Mac screenshots are 16:10 (2880×1800 and the like)."
        end
        problems << "#{File.basename(shot)} has an alpha channel; App Store screenshots must not." if info[:alpha]
      end
    end
    problems << "No screenshots under #{dir}." if Dir[File.join(dir, "*", "*.png")].empty?
    problems
  end

  def image_info(path)
    output = IO.popen(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", path], err: File::NULL, &:read)
    width = output[/pixelWidth: (\d+)/, 1]
    height = output[/pixelHeight: (\d+)/, 1]
    return nil unless width && height
    { width: width.to_i, height: height.to_i, alpha: output[/hasAlpha: (\w+)/, 1] == "yes" }
  rescue Errno::ENOENT
    nil
  end

  # Breaks a copy of the listing on purpose and expects each break to be caught.
  def self_test(fastlane)
    failures = []
    baseline = problems(fastlane)
    failures << "The listing itself has problems:\n  #{baseline.join("\n  ")}" unless baseline.empty?

    cases = {
      "subtitle over 30" => ->(dir) { File.write(File.join(dir, "metadata/en-US/subtitle.txt"), "A" * 31) },
      "keywords over 100" => ->(dir) { File.write(File.join(dir, "metadata/en-US/keywords.txt"), (["usage"] + (1..30).map { |i| "k#{i}" }).join(",")) },
      "promotional text over 170" => ->(dir) { File.write(File.join(dir, "metadata/en-US/promotional_text.txt"), "a" * 171) },
      "description over 4000" => ->(dir) { File.open(File.join(dir, "metadata/en-US/description.txt"), "a") { |f| f.write("x" * 4000) } },
      "name over 30" => ->(dir) { File.write(File.join(dir, "metadata/en-US/name.txt"), "Headroom for every coding agent!") },
      "a trademark in keywords" => ->(dir) { File.write(File.join(dir, "metadata/en-US/keywords.txt"), "usage,Claude,quota") },
      "a keyword from the subtitle" => ->(dir) { File.write(File.join(dir, "metadata/en-US/keywords.txt"), "usage,limit,quota") },
      "the app name as a keyword" => ->(dir) { File.write(File.join(dir, "metadata/en-US/keywords.txt"), "usage,Headroom,quota") },
      "a trademark in the subtitle" => ->(dir) { File.write(File.join(dir, "metadata/en-US/subtitle.txt"), "Copilot limits at a glance") },
      "a URL elsewhere" => ->(dir) { File.write(File.join(dir, "metadata/en-US/support_url.txt"), "http://example.com") },
      "no non-affiliation line" => ->(dir) { File.write(File.join(dir, "metadata/en-US/description.txt"), "Headroom.") },
      "Codex named without OpenAI in the non-affiliation line" => ->(dir) {
        File.write(File.join(dir, "metadata/en-US/description.txt"),
                   "Works with OpenAI Codex. It isn't made by, affiliated with or endorsed by Anthropic.")
      },
      "\"AI coding\" in the promotional text" => ->(dir) {
        File.write(File.join(dir, "metadata/en-US/promotional_text.txt"), "Your AI coding limits, one glance away.")
      },
      "\"AI coding\" in the review notes" => ->(dir) {
        File.write(File.join(dir, "metadata/review_information/notes.txt"), "Show sample data. A menu bar app for AI-coding limits.")
      },
      "a 12+ rating" => ->(dir) { File.write(File.join(dir, "rating_config.json"), JSON.generate("violenceRealistic" => "FREQUENT_OR_INTENSE")) },
      "a copyright with ©" => ->(dir) { File.write(File.join(dir, "metadata/copyright.txt"), "© 2026 Nio Martinez") }
    }
    cases.each do |label, breakage|
      Dir.mktmpdir("headroom-metadata") do |tmp|
        copy = File.join(tmp, "fastlane")
        FileUtils.mkdir_p(copy)
        %w[metadata rating_config.json].each { |item| FileUtils.cp_r(File.join(fastlane, item), copy) }
        # Screenshots are checked once above; the copies only need a valid set.
        FileUtils.mkdir_p(File.join(copy, "screenshots"))
        FileUtils.cp_r(File.join(fastlane, "screenshots", "en-US"), File.join(copy, "screenshots"))
        breakage.call(copy)
        failures << "Not caught: #{label}." if problems(copy).empty?
      end
    end
    failures
  end
end

if $PROGRAM_NAME == __FILE__
  default_root = File.expand_path("../..", __dir__)
  if ARGV.first == "--self-test"
    failures = MetadataCheck.self_test(File.join(ARGV[1] || default_root, "fastlane"))
    if failures.empty?
      puts "check-metadata self-test: every break was caught."
      exit 0
    end
    warn failures.join("\n")
    exit 1
  end

  root = File.expand_path(ARGV.first || default_root)
  problems = MetadataCheck.problems(File.join(root, "fastlane"))
  if problems.empty?
    puts "App Store metadata: OK (lengths, trademarks, URLs, categories, age rating, screenshots)."
    exit 0
  end
  warn "App Store metadata has #{problems.size} problem(s):"
  problems.each { |problem| warn "  - #{problem}" }
  exit 1
end
