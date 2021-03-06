# frozen_string_literal: true

require 'json'
require_relative './retrieval'
require_relative './logging'

module PeachMelpa
  module Parsing
    SCREENSHOT_FOLDER = "#{::Rails.root}/tmp/screenshots/"

    def self.looks_like_theme?(name)
      name.end_with? '-theme', '-themes'
    end

    def self.select_themes(data)
      data.select { |name, _val| looks_like_theme? name }
    end

    def self.parse_theme(name, meta, opts = {})
      PeachMelpa::Log.info(name) { 'trying to find theme' }

      version = meta['ver'].join('.')
      description = meta['desc']
      url = meta['props']['url']
      authors = [].concat(meta['props']['authors'] || []).join(', ')
      kind = meta['type']

      theme = Theme.find_or_create_by(name: name)

      if theme.older_than?(version) && !theme.blacklisted? || (opts[:force] == true)
        PeachMelpa::Log.info(name) { 'theme eligible for update...' }
        theme.update_screenshots!(
          version: version,
          description: description,
          url: url,
          authors: authors,
          kind: kind
        )
      else
        PeachMelpa::Log.info(name) { 'skipped because either up-to-date or blacklisted.' }
      end
    end

    def self.start_daemon
      PeachMelpa::Log.info { 'start Emacs daemon...' }
      `ps aux | grep "emacs --daemon=peach" | grep -v "grep" | awk '{ print $2 }' | xargs kill`
      `emacs --daemon=peach -Q -l lib/take-screenshot.el`
    end

    def self.stop_daemon
      PeachMelpa::Log.info { 'stopping Emacs daemon...' }
      `emacsclient -s peach -e '(kill-emacs)'`
    end

    def self.pick_updated_themes(opts = {})
      stop_daemon
      start_daemon

      PeachMelpa::Log.info { 'starting to parse themes' }
      data = JSON.parse(IO.read(PeachMelpa::Retrieval::ARCHIVE_PATH))

      # FIXME: harmonise interface so it can be something predicate-based like
      # filters = opts[:only] ? self.find_theme(opts[:only]) : self.looks_like_theme?
      # themes = data.select(filters)
      themes = if opts[:only]
                 data.select { |entry| entry == opts[:only] }
               else
                 select_themes data
               end

      PeachMelpa::Log.info { "captured #{themes.length} themes to update " }

      Dir.mkdir SCREENSHOT_FOLDER unless Dir.exist? SCREENSHOT_FOLDER

      args = nil
      args = { force: true } unless opts[:force].nil?

      themes.each do |name, props|
        send :parse_theme, name, props, *[args].reject(&:nil?)
      end

      stop_daemon
    end
  end
end
