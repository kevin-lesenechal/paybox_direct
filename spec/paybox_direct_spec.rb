# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'paybox_direct'
require 'ostruct'

RSpec.describe PayboxDirect do
  before do
    PayboxDirect.config.site       = SITE
    PayboxDirect.config.rank       = RANK
    PayboxDirect.config.login      = LOGIN
    PayboxDirect.config.password   = PASSWORD
    PayboxDirect.config.ref_prefix = REF_PREFIX
    PayboxDirect.config.activity   = ENV.key?("PB_ACTIVITY") ? ENV["PB_ACTIVITY"].to_i : nil
    PayboxDirect.config.bank       = ENV.key?("PB_BANK") ? ENV["PB_BANK"] : nil
    PayboxDirect.config.is_prod    = false
  end

  context "authorization and debit" do
    it "should make a auth-only without subscription" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444" if !DO_CALLS

      req = PayboxDirect.authorize(
        ref:       "auth_only",
        amount:    14.29,
        currency:  :EUR,
        cc_number: CC_NUMBER,
        cc_expire: CC_EXPIRE,
        cc_cvv:    CC_CVV
      )

      expect(req.vars).to include({
        "TYPE"      => "00001",
        "REFERENCE" => REF_PREFIX + "auth_only",
        "MONTANT"   => "0000001429",
        "DEVISE"    => "978",
        "PORTEUR"   => CC_NUMBER.gsub("-", ""),
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
      end
    end

    it "should make a auth-only and create a subscriber" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444&PORTEUR=my_wallet_code" if !DO_CALLS

      req = PayboxDirect.authorize(
        ref:        "auth_only_new_subscriber",
        amount:     25,
        currency:   :EUR,
        cc_number:  CC_NUMBER,
        cc_expire:  CC_EXPIRE,
        cc_cvv:     CC_CVV,
        subscriber: "my_sub_id"
      )

      expect(req.vars).to include({
        "TYPE"      => "00056",
        "REFERENCE" => REF_PREFIX + "auth_only_new_subscriber",
        "MONTANT"   => "0000002500",
        "DEVISE"    => "978",
        "PORTEUR"   => CC_NUMBER.gsub("-", ""),
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV,
        "REFABONNE" => REF_PREFIX + "my_sub_id"
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
        expect(req.response[:wallet]).to eq "CMDLpStLLLs"
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
        expect(req.response[:wallet]).to eq "my_wallet_code"
      end
    end

    it "should make a auth-only on a subscriber" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444" if !DO_CALLS

      if DO_CALLS
        req = PayboxDirect.authorize(
          ref:        "auth_only_subscriber_create",
          amount:     1,
          currency:   :EUR,
          cc_number:  CC_NUMBER,
          cc_expire:  CC_EXPIRE,
          cc_cvv:     CC_CVV,
          subscriber: "my_sub_id2"
        )
        wallet = req.response[:wallet]
      else
        wallet = "my_wallet_code"
      end

      req = PayboxDirect.authorize(
        ref:        "auth_only_subscriber",
        amount:     25,
        currency:   :EUR,
        wallet:     wallet,
        cc_expire:  CC_EXPIRE,
        cc_cvv:     CC_CVV,
        subscriber: "my_sub_id2"
      )

      expect(req.vars).to include({
        "TYPE"      => "00051",
        "REFERENCE" => REF_PREFIX + "auth_only_subscriber",
        "MONTANT"   => "0000002500",
        "DEVISE"    => "978",
        "PORTEUR"   => wallet,
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV,
        "REFABONNE" => REF_PREFIX + "my_sub_id2"
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
      end
    end

    it "should make a debit without subscription" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444" if !DO_CALLS

      req = PayboxDirect.debit(
        ref:       "debit",
        amount:    50.3,
        currency:  :EUR,
        cc_number: CC_NUMBER,
        cc_expire: CC_EXPIRE,
        cc_cvv:    CC_CVV
      )

      expect(req.vars).to include({
        "TYPE"      => "00003",
        "REFERENCE" => REF_PREFIX + "debit",
        "MONTANT"   => "0000005030",
        "DEVISE"    => "978",
        "PORTEUR"   => CC_NUMBER.gsub("-", ""),
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
      end
    end

    it "should make a debit and create a subscriber" do
      if !DO_CALLS
        allow_any_instance_of(PayboxDirect::Request).to receive(:run_http_post!) { |req|
          if req.vars["TYPE"] == "00056"
            OpenStruct.new({
              code: "200",
              body: "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444&PORTEUR=my_wallet_code"
            })
          else
            OpenStruct.new({
              code: "200",
              body: "CODEREPONSE=00000&COMMENTAIRE="
            })
          end
        }
      end

      expect(PayboxDirect).to receive(:debit_authorization).with(
        amount:         50.3,
        currency:       :EUR,
        request_id:     DO_CALLS ? be_a(Fixnum) : 111111,
        transaction_id: DO_CALLS ? be_a(Fixnum) : 2222222
      ).and_call_original

      req = PayboxDirect.debit(
        ref:        "debit_new_subscriber",
        amount:     50.3,
        currency:   :EUR,
        cc_number:  CC_NUMBER,
        cc_expire:  CC_EXPIRE,
        cc_cvv:     CC_CVV,
        subscriber: "my_sub_id3"
      )

      expect(req.vars).to include({
        "TYPE"      => "00056",
        "REFERENCE" => REF_PREFIX + "debit_new_subscriber",
        "MONTANT"   => "0000005030",
        "DEVISE"    => "978",
        "PORTEUR"   => CC_NUMBER.gsub("-", ""),
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV,
        "REFABONNE" => REF_PREFIX + "my_sub_id3"
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
        expect(req.response[:wallet]).to eq "CMDLpStLLLs"
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
        expect(req.response[:wallet]).to eq "my_wallet_code"
      end
    end

    it "should make a debit on a subscriber" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=&NUMAPPEL=0000111111&NUMTRANS=0002222222&AUTORISATION=444444" if !DO_CALLS

      if DO_CALLS
        req = PayboxDirect.authorize(
          ref:        "debit_subscriber_create",
          amount:     1,
          currency:   :EUR,
          cc_number:  CC_NUMBER,
          cc_expire:  CC_EXPIRE,
          cc_cvv:     CC_CVV,
          subscriber: "my_sub_id4"
        )
        wallet = req.response[:wallet]
      else
        wallet = "my_wallet_code"
      end

      req = PayboxDirect.debit(
        ref:        "debit_subscriber",
        amount:     25,
        currency:   :EUR,
        wallet:     wallet,
        cc_expire:  CC_EXPIRE,
        cc_cvv:     CC_CVV,
        subscriber: "my_sub_id4"
      )

      expect(req.vars).to include({
        "TYPE"      => "00053",
        "REFERENCE" => REF_PREFIX + "debit_subscriber",
        "MONTANT"   => "0000002500",
        "DEVISE"    => "978",
        "PORTEUR"   => wallet,
        "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
        "CVV"       => CC_CVV,
        "REFABONNE" => REF_PREFIX + "my_sub_id4"
      })

      if DO_CALLS
        expect(req.response[:request_id]).to be_a Fixnum
        expect(req.response[:transaction_id]).to be_a Fixnum
        expect(req.response[:authorization]).to be_nil
      else
        expect(req.response[:request_id]).to eq 111111
        expect(req.response[:transaction_id]).to eq 2222222
        expect(req.response[:authorization]).to eq 444444
      end
    end

    it "should make debit on a prior auth-only" do
      stub_response "CODEREPONSE=00000&COMMENTAIRE=" if !DO_CALLS

      if DO_CALLS
        req = PayboxDirect.authorize(
          ref:        "auth_to_debit",
          amount:     18.20,
          currency:   :EUR,
          cc_number:  CC_NUMBER,
          cc_expire:  CC_EXPIRE,
          cc_cvv:     CC_CVV
        )
        req_id = req.response[:request_id]
        trans_id = req.response[:transaction_id]
      else
        req_id = 111111
        trans_id = 2222222
      end

      req = PayboxDirect.debit_authorization(
        amount:         18.20,
        currency:       :EUR,
        request_id:     req_id,
        transaction_id: trans_id
      )

      expect(req.vars).to include({
        "TYPE"      => "00002",
        "MONTANT"   => "0000001820",
        "DEVISE"    => "978",
        "NUMAPPEL"  => req_id.to_s.rjust(10, "0"),
        "NUMTRANS"  => trans_id.to_s.rjust(10, "0")
      })
    end
  end

  it "should cancel an operation" do
    stub_response "CODEREPONSE=00000&COMMENTAIRE=" if !DO_CALLS

    if DO_CALLS
      req = PayboxDirect.debit(
        ref:        "debit_to_cancel",
        amount:     38.14,
        currency:   :EUR,
        cc_number:  CC_NUMBER,
        cc_expire:  CC_EXPIRE,
        cc_cvv:     CC_CVV
      )
      req_id = req.response[:request_id]
      trans_id = req.response[:transaction_id]
    else
      req_id = 111111
      trans_id = 2222222
    end

    req = PayboxDirect.cancel(
      amount:         38.14,
      currency:       :EUR,
      ref:            "debit_to_cancel",
      cc_expire:      CC_EXPIRE,
      cc_cvv:         CC_CVV,
      request_id:     req_id,
      transaction_id: trans_id
    )

    expect(req.vars).to include({
      "TYPE"      => "00005",
      "REFERENCE" => REF_PREFIX + "debit_to_cancel",
      "MONTANT"   => "0000003814",
      "DEVISE"    => "978",
      "DATEVAL"   => CC_EXPIRE.strftime("%m%y"),
      "CVV"       => CC_CVV,
      "NUMAPPEL"  => req_id.to_s.rjust(10, "0"),
      "NUMTRANS"  => trans_id.to_s.rjust(10, "0")
    })
  end

  it "should refund a debited payment" do
    stub_response "CODEREPONSE=00000&COMMENTAIRE="

    req = PayboxDirect.refund(
      amount:         10.20,
      currency:       :EUR,
      request_id:     111111,
      transaction_id: 2222222
    )

    expect(req.vars).to include({
      "TYPE"      => "00014",
      "MONTANT"   => "0000001020",
      "DEVISE"    => "978",
      "NUMAPPEL"  => "0000111111",
      "NUMTRANS"  => "0002222222"
    })
  end
end
