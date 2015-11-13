# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'paybox_direct'

RSpec.describe PayboxDirect::Request do
  before do
    PayboxDirect.config.site       = "444444"
    PayboxDirect.config.rank       = "88"
    PayboxDirect.config.login      = "my_login"
    PayboxDirect.config.password   = "my_password"
    PayboxDirect.config.version    = 104
    PayboxDirect.config.activity   = 24
    PayboxDirect.config.bank       = "ems"
    PayboxDirect.config.is_prod    = false
  end

  it "should assign variables" do
    fake_time = DateTime.parse("2015-09-12 13:32:51").to_time.utc
    expect(Time).to receive(:new).with(no_args).at_least(:once).and_return(fake_time)

    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    expect(req.vars).to eq({
      "VERSION"     => "00104",
      "SITE"        => "0444444",
      "RANG"        => "88",
      "CLE"         => "my_password",
      "DATEQ"       => "12092015133251",
      "NUMQUESTION" => "0133251000",
      "ACTIVITE"    => "024",
      "ACQUEREUR"   => "ems",
      "VAR1"        => "VAL1",
      "VAR2"        => "VAL2"
    })
  end

  it "should parse result error codes" do
    stub_response "CODEREPONSE=00008&COMMENTAIRE=My+error+description"

    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    req.execute!

    expect(req).to be_failed
    expect(req.error_code).to eq 8
    expect(req.error_comment).to eq "My error description"
  end

  it "calls request callbacks" do
    expect_any_instance_of(Net::HTTP).to receive(:request){
      OpenStruct.new({
        code: "200",
        body: "CODEREPONSE=00000&COMMENTAIRE=OK"
      })
    }
    cb = proc {}
    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    PayboxDirect::Request.on_request &cb
    expect(cb).to receive(:call).with(req)
    req.execute!
  end

  it "should raise ServerUnavailable in dev" do
    was_prod = PayboxDirect.config.is_prod
    PayboxDirect.config.is_prod = false
    dev_uri = URI(PayboxDirect::DEV_URL)

    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    expect_any_instance_of(Net::HTTP).to receive(:request).and_raise(SocketError)
    expect {
      req.execute!
    }.to raise_error(PayboxDirect::ServerUnavailableError)

    PayboxDirect.config.is_prod = was_prod
  end

  it "should fallback on alt URL in prod" do
    was_prod = PayboxDirect.config.is_prod
    PayboxDirect.config.is_prod = true
    prod_uri = URI(PayboxDirect::PROD_URL)
    prod_fallback_uri = URI(PayboxDirect::PROD_FALLBACK_URL)

    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    expect(req).to receive(:run_http_post!).with(prod_uri).and_raise(PayboxDirect::ServerUnavailableError)
    expect(req).to receive(:run_http_post!).with(prod_fallback_uri) {
      OpenStruct.new({
        code: "200",
        body: "CODEREPONSE=00000&COMMENTAIRE=OK"
      })
    }
    req.execute!
    expect(req).not_to be_failed

    PayboxDirect.config.is_prod = was_prod
  end

  it "should raise ServerUnavailable in prod" do
    was_prod = PayboxDirect.config.is_prod
    PayboxDirect.config.is_prod = true
    prod_uri = URI(PayboxDirect::PROD_URL)
    prod_fallback_uri = URI(PayboxDirect::PROD_FALLBACK_URL)

    req = PayboxDirect::Request.new("VAR1" => "VAL1", "VAR2" => "VAL2")
    expect(req).to receive(:run_http_post!).with(prod_uri).and_raise(PayboxDirect::ServerUnavailableError)
    expect(req).to receive(:run_http_post!).with(prod_fallback_uri).and_raise(PayboxDirect::ServerUnavailableError)
    expect {
      req.execute!
    }.to raise_error(PayboxDirect::ServerUnavailableError)

    PayboxDirect.config.is_prod = was_prod
  end
end
