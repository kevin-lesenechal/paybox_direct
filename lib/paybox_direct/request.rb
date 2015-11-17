# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'rack'

class PayboxDirect::Request
  attr_reader   :vars, :post_request, :fields, :http_resp
  attr_accessor :response, :http_connection

  @@request_callbacks = []

  def self.on_request(&block)
    @@request_callbacks << block
  end

  def initialize(vars, http_conn = nil)
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
    @http_connection = http_conn
    @response = {}
  end

  # Executes the POST request on the Paybox server.
  #
  # == Raises:
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def execute!
    use_alt = false
    begin
      resp = run_http_post!(self.class.uri(use_alt))
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

  def request_id
    raise "Not executed yet" if @fields.nil?
    return @fields["NUMAPPEL"].to_i
  end

  def error_code
    raise "Not executed yet" if @fields.nil?
    return @fields["CODEREPONSE"].to_i
  end

  def error_comment
    raise "Not executed yet" if @fields.nil?
    return @fields["COMMENTAIRE"]
  end

  def self.uri(alt = false)
    prod_url = alt ? PayboxDirect::PROD_FALLBACK_URL : PayboxDirect::PROD_URL
    return PayboxDirect.config.is_prod ? prod_url : PayboxDirect::DEV_URL
  end

  def self.http_connection(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    return http
  end

private

  def run_http_post!(uri)
    http = @http_connection || self.class.http_connection(uri)
    @post_request = Net::HTTP::Post.new(uri.request_uri)
    @post_request.set_form_data(@vars)
    begin
      @http_resp = http.request(@post_request)
    rescue
      raise PayboxDirect::ServerUnavailableError
    end
    @@request_callbacks.each{ |proc| proc.call(self) }
    return @http_resp
  end
end
