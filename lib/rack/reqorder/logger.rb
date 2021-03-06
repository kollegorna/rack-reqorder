module Rack::Reqorder
  class Logger
    include Rack::Reqorder::Models

    def initialize(app)
      @app = app
    end

    def call(environment)
      rack_request = Rack::Request.new(
        environment.clone.tap{|h|
          h[Rack::RACK_INPUT] = StringIO.new(request_body(environment))
        }
      )

      http_request = record_request(rack_request) if conf.request_monitoring

      start = Time.now.to_f
      begin
        status, headers, body = @app.call(environment)
        rack_response = Rack::Response.new(body, status, headers)
      rescue => exception
        rack_response = log_exception(exception, rack_request) if conf.exception_monitoring

        raise exception
      ensure
        record_statistics(rack_request, rack_response, Time.now.to_f - start)
      end
      record_response(rack_response, http_request) if conf.request_monitoring

      return [status, headers, body]
    end

  private
    #StringIO behaves quite weirdly
    def request_body(environment)
      str = environment[Rack::RACK_INPUT].read.to_s
      environment[Rack::RACK_INPUT] = StringIO.new(str)

      return str
    end

    def record_statistics(rack_request, rack_response, response_time)
      if rack_response && conf.metrics_monitoring
        save_statistics(
          rack_request: rack_request,
          rack_response: rack_response,
          response_time: response_time
        )
      end
    end

    def record_request(rack_request)
      request_headers = extract_all_headers(rack_request.env)
      recording = nil

      Recording.enabled.all.each do |rec|
        if request_headers[rec.rack_http_header] == rec.http_header_value
          recording = rec and break
        end
      end

      if recording
        return save_http_request(rack_request, recording)
      end
    end

    def record_response(rack_response, http_request)
      if http_request && http_request.recording
        return save_http_response(rack_response, http_request)
      end
    end

    def extract_all_headers(env)
      Hash[
        env.select{|k,v|
          k.start_with? 'HTTP_'
        }.map{|k,v|
          [k.gsub('HTTP_','').upcase, v]
        }.select{|k,v|
          k != 'COOKIE'
        }
      ]
    end

    def route_template(request_path:, request_method:)
      Rack::Reqorder.recognize_path(request_path, {method: request_method})
    end

    def save_statistics(rack_request:, rack_response:, response_time:)
      route_path = RoutePath.find_or_create_by({
        route: route_template({
          #response_status: rack_response.status,
          request_path: rack_request.path,
          request_method: rack_request.request_method
        }),
        http_method: rack_request.request_method
      })

      [:all.to_s, DateTime.now.utc.hour.to_s].each do |key|
        statistic = route_path.send("statistic_#{key}".to_sym)

        if key != :all.to_s && statistic && statistic.created_at.to_date < DateTime.now.utc.to_date
          statistic = route_path.send("create_statistic_#{key}")
        end

        if statistic.nil?
          statistic = route_path.send("create_statistic_#{key}")
        end

        statistic.inc({
          statuses_2xx: (rack_response.status < 300 && rack_response.status >= 200)? 1: 0,
          statuses_3xx: (rack_response.status < 400 && rack_response.status >= 300)? 1: 0,
          statuses_4xx: (rack_response.status < 500 && rack_response.status >= 400)? 1: 0,
          statuses_401: (rack_response.status == 401) ? 1 : 0,
          statuses_404: (rack_response.status == 404) ? 1 : 0,
          statuses_422: (rack_response.status == 422) ? 1 : 0,
          statuses_5xx: (rack_response.status < 600 && rack_response.status >= 500)? 1: 0,
          http_requests_count: 1,
          xhr_count: rack_request.xhr? ? 1 : 0,
          ssl_count: rack_request.ssl? ? 1 : 0,
        })

        statistic.recalculate_average!(response_time)

        route_path.save!
        route_path.send("statistic_#{key}".to_sym).save!
      end
    end


    def save_http_request(rack_request, recording = nil)
      if not recording
        route_path = RoutePath.find_or_create_by({
          route: Rack::Reqorder.recognize_path(rack_request.path),
          http_method: rack_request.request_method
        })
      end

      HttpRequest.create({
        ip: rack_request.ip,
        url: rack_request.url,
        body: rack_request.body.read.to_s,
        scheme: rack_request.scheme,
        base_url: rack_request.base_url,
        port: rack_request.port,
        path: rack_request.path,
        full_path: rack_request.fullpath,
        http_method: rack_request.request_method,
        headers: extract_all_headers(rack_request.env),
        params: rack_request.params,
        ssl: rack_request.ssl?,
        xhr: rack_request.xhr?,
        route_path: recording ? nil : route_path,
        recording: recording ? recording : nil
      })
    end

    def save_http_response(rack_response, http_request)
      HttpResponse.create(
        headers: rack_response.headers,
        body: rack_response.body.first,
        status: rack_response.status.to_i,
        length: rack_response.length,
        http_request: http_request,
        recording: http_request.recording.nil? ? nil : http_request.recording
      )
    end

    def log_exception(exception, rack_request)
      http_request = save_http_request(rack_request)

      bc = BacktraceCleaner.new
      bc.add_filter   { |line| line.gsub(Rails.root.to_s, '') }
      bc.add_silencer { |line| line =~ /gems/ }

      application_trace = bc.clean(exception.backtrace)

      path = line = nil

      if not application_trace.blank?
        path, line, _ = application_trace.first.split(':')
      else
        path, line, _ = exception.backtrace.first.split(':')
      end

      app_fault = AppFault.find_or_create_by(
        e_class: exception.class,
        line: line.to_i,
        filepath: path[1..-1],
        environment: conf.environment
      )

      AppException.create(
        e_class: exception.class,
        message: exception.message,
        application_trace: application_trace,
        full_trace: exception.backtrace,
        line: line.to_i,
        filepath: path[1..-1],
        source_extract: source_fragment(path[1..-1], line.to_i),
        app_fault: app_fault,
        http_request: http_request
      )

      return HttpResponse.create(
        status: 500,
        http_request: http_request
      )
    end

    def source_fragment(path, line)
      return unless Rails.respond_to?(:root) && Rails.root

      full_path = Rails.root.join(path)
      if File.exist?(full_path)
        File.open(full_path, "r") do |file|
          start = [line - 3, 0].max
          lines = file.each_line.drop(start).take(6)
          Hash[*(start+1..(lines.count+start)).zip(lines).flatten]
        end
      end
    end

    def conf
      Rack::Reqorder.configuration
    end
  end
end
