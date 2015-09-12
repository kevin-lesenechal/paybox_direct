# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'rack'

class PayboxDirect::Request
  attr_reader   :vars, :post_request, :fields
  attr_accessor :response

  def initialize(vars)
    defaults = {
      "VERSION"     => PayboxDirect.config.version.to_s.rjust(5, "0"),
      "SITE"        => PayboxDirect.config.site.to_s.rjust(7, "0"),
      "RANG"        => PayboxDirect.config.rank.to_s.rjust(2, "0"),
      "CLE"         => PayboxDirect.config.password,
      "DATEQ"       => Time.new.utc.strftime("%d%m%Y%H%M%S"),
      "NUMQUESTION" => Time.new.utc.strftime("%H%M%S%L").rjust(10, "0")
    }
    if !PayboxDirect.config.activity.nil?
      defaults["ACTIVITE"] = PayboxDirect.config.activity.to_s.rjust(3, "0")
    end
    if !PayboxDirect.config.bank.nil?
      defaults["ACQUEREUR"] = PayboxDirect.config.bank
    end
    @vars = defaults.merge(vars)

    @post_request = nil
    @fields = nil
    @response = {}
  end

  # Executes the POST request on the Paybox server.
  #
  # == Raises:
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def execute!
    use_alt = false
    begin
      begin
        prod_url = use_alt ? PayboxDirect::PROD_FALLBACK_URL : PayboxDirect::PROD_URL
        uri = URI(PayboxDirect.config.is_prod ? prod_url : PayboxDirect::DEV_URL)
        resp = run_http_post!(uri)
      rescue
        raise PayboxDirect::ServerUnavailableError
      end
      raise PayboxDirect::ServerUnavailableError if resp.code != "200"
      @fields = Rack::Utils.parse_query(resp.body)
      if !@fields.has_key?("CODEREPONSE") or @fields["CODEREPONSE"] == "00001"
        raise PayboxDirect::ServerUnavailableError
      end
    rescue PayboxDirect::ServerUnavailableError => e
      raise e if use_alt or !PayboxDirect.config.is_prod
      use_alt = true
      sleep 1
      retry
    end
  end

  def failed?
    raise "Not executed yet" if @fields.nil?
    return @fields["CODEREPONSE"] != "00000"
  end

  def error_code
    raise "Not executed yet" if @fields.nil?
    return @fields["CODEREPONSE"].to_i
  end

  def error_comment
    raise "Not executed yet" if @fields.nil?
    return @fields["COMMENTAIRE"]
  end

  def self.http_connection(uri)
    # We may want to execute multiple requests on a single HTTP connection in the future.
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    return http
  end

private

  def run_http_post!(uri)
    http = self.class.http_connection(uri)
    @post_request = Net::HTTP::Post.new(uri.request_uri)
    @post_request.set_form_data(@vars)
    resp = http.request(@post_request)
    return resp
  end
end
