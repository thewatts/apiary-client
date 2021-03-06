# encoding: utf-8
require 'rest_client'
require 'rack'
require 'ostruct'
require 'json'

require "apiary/common"

module Apiary
  module Command
    # Display preview of local blueprint file
    class Preview

      BROWSERS = {
        :safari => "Safari",
        :chrome => "Google Chrome",
        :firefox => "Firefox"
      }

      attr_reader :options

      def initialize(opts)
        @options = OpenStruct.new(opts)
        @options.path         ||= "apiary.apib"
        @options.api_host     ||= "api.apiary.io"
        @options.headers      ||= {:accept => "text/html", :content_type => "text/plain"}
        @options.port         ||= 8080
        @options.proxy        ||= ENV['http_proxy']
        @options.server       ||= false
      end

      def execute
        if @options.server
          server
        else
          show
        end
      end

      def server
        run_server
      end

      def show
        generate_static(@options.path)
      end

      def validate_apib_file(apib_file)
        common = Apiary::Common.new
        common.validate_apib_file(apib_file)
      end

      def path
        @options.path || "#{File.basename(Dir.pwd)}.apib"
      end

      def browser
        BROWSERS[@options.browser]  || nil
      end

      def rack_app(&block)
        Rack::Builder.new do
          run lambda { |env| [200, Hash.new, [block.call]] }
        end
      end

      def run_server
        app = self.rack_app do
          self.query_apiary(@options.api_host, @options.path)
        end

        Rack::Server.start(:Port => @options.port, :app => app)
      end

      def preview_path(path)
        basename = File.basename(@options.path)
        "/tmp/#{basename}-preview.html"
      end

      def query_apiary(host, path)
        url  = "https://#{host}/blueprint/generate"
        if validate_apib_file(path)
          begin
            data = File.read(path)
          rescue
            abort "File #{path} not found."
          end

          RestClient.proxy = @options.proxy

          begin
            RestClient.post(url, data, @options.headers)
          rescue RestClient::BadRequest => e
            err = JSON.parse e.response
            if err.has_key? 'parserError'
              abort "#{err['message']}: #{err['parserError']} (Line: #{err['line']}, Column: #{err['column']})"
            else
              abort "Apiary service responded with an error: #{err['message']}"
            end
          rescue RestClient::Exception => e
            abort "Apiary service responded with an error: #{e.message}"
          end
        else
          abort "Sorry, Apiary can't display invalid blueprint."
        end
      end

      # TODO: add linux and windows systems
      def open_generated_page(path)
        exec "open #{browser_options} #{path}"
      end

      def write_generated_path(path, outfile)
        File.write(outfile, File.read(path))
      end

      def generate_static(path)
        File.open(preview_path(path), "w") do |file|
          file.write(query_apiary(@options.api_host, path))
          @options.output ? write_generated_path(file.path, @options.output) : open_generated_page(file.path)
        end
      end

      private
        def browser_options
          "-a #{BROWSERS[@options.browser.to_sym]}" if @options.browser
        end
    end
  end
end
