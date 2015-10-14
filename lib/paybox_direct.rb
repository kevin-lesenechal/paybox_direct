# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'ostruct'
require 'net/http'

module PayboxDirect
  DEV_URL           = 'https://preprod-ppps.paybox.com/PPPS.php'
  PROD_URL          = 'https://ppps.paybox.com/PPPS.php'
  PROD_FALLBACK_URL = 'https://ppps1.paybox.com/PPPS.php'

  CURRENCIES = {
    :AUD => 36,
    :CAD => 124,
    :CHF => 756,
    :DKK => 208,
    :EUR => 978,
    :GBP => 826,
    :HKD => 344,
    :JPY => 392,
    :USD => 840
  }

  @@config = OpenStruct.new({
    site:       nil,  # Your site number, see your Paybox contract
    rank:       nil,  # Your rank number, see your Paybox contract
    login:      nil,  # Your login, see your Paybox contract
    password:   nil,  # Your password, see your Paybox contract
    is_prod:    true, # Set to false to use the Paybox test server
    ref_prefix: '',   # A prefix to all references including subscriber IDs
    version:    104,  # The protocol version, 103 for Paybox Direct, 104 for Paybox Direct Plus
    activity:   nil,  # The activity code (ACTIVITE), see Paybox documentation
    bank:       nil   # The ACQUEREUR variable, let nil if you don't have special requirements
  })

  def self.config
    @@config
  end

  # Executes an authorization with or without debit.
  #
  # == Options:
  # * amount:     The decimal amount, e.g. 49.9 for €49.90 (or other currency)
  # * currency:   The currency code, e.g. :EUR
  # * ref:        The application reference for this authorization
  # * cc_number:  The credit card number, e.g. "1234123412341234" (if not subscribed)
  # * wallet:     The wallet number (if subscribed)
  # * cc_expire:  The credit card expiration date, e.g. Date.new(2015, 10, 1)
  # * cc_cvv:     The credit card CVV, e.g. "123"
  # * subscriber: (optional) A subscriber ID
  # * debit:      (Bool) if true, will debit (default false)
  #
  # If a subscriber ID is provided:
  # * and `wallet` is provided, will execute a #51 operation (#53 if debit);
  # * and `wallet` is NOT provided, will execute a #56 operation (then #2 if debit);
  # otherwise, will execute a #1 operation (#3 if debit).
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request with these response variables:
  # * transaction_id: The Paybox transaction ID (NUMTRANS)
  # * wallet:         (if new subscription) The created wallet code (PORTEUR)
  #
  # == Raises:
  # * PayboxDirect::AuthorizationError, if authorization fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.authorize(opts)
    raise ArgumentError, "Expecting hash" unless opts.is_a? Hash
    raise ArgumentError, "Expecting `amount` option" unless opts.has_key? :amount
    raise ArgumentError, "Expecting `currency` option" unless opts.has_key? :currency
    raise ArgumentError, "Expecting `ref` option" unless opts.has_key? :ref
    raise ArgumentError, "Expecting `cc_expire` option" unless opts.has_key? :cc_expire
    raise ArgumentError, "Expecting `cc_cvv` option" unless opts.has_key? :cc_cvv
    raise ArgumentError, "amount: Expecting Numeric" unless opts[:amount].is_a? Numeric
    raise ArgumentError, "currency: Not supported" unless CURRENCIES.has_key? opts[:currency]
    raise ArgumentError, "cc_expire: Expecting Date" unless opts[:cc_expire].is_a? Date
    opts[:debit] = false if !opts.has_key? :debit

    if opts.has_key? :subscriber
      if opts.has_key? :wallet
        raise ArgumentError, "cc_number: Unexpected when `wallet` provided" if opts.has_key? :cc_number
        op_code = opts[:debit] ? 53 : 51
      else
        raise ArgumentError, "Expecting `cc_number` option" unless opts.has_key? :cc_number
        op_code = 56 # Paybox can't create a new subscriber with immediate debit
      end
    else
      raise ArgumentError, "Expecting `cc_number` option" unless opts.has_key? :cc_number
      raise ArgumentError, "Unexpected `wallet` option" if opts.has_key? :wallet
      op_code = opts[:debit] ? 3 : 1
    end

    vars = {
      "TYPE"      => op_code.to_s.rjust(5, "0"),
      "REFERENCE" => @@config.ref_prefix + opts[:ref],
      "MONTANT"   => (opts[:amount].round(2) * 100).round.to_s.rjust(10, "0"),
      "DEVISE"    => CURRENCIES[opts[:currency]].to_s.rjust(3, "0"),
      "PORTEUR"   => opts.has_key?(:wallet) ? opts[:wallet] : opts[:cc_number].gsub(/[ -.]/, ""),
      "DATEVAL"   => opts[:cc_expire].strftime("%m%y"),
      "CVV"       => opts[:cc_cvv]
    }
    if opts.has_key? :subscriber
      vars["REFABONNE"] = @@config.ref_prefix + opts[:subscriber]
    end
    req = Request.new(vars)
    req.execute!

    if req.failed?
      raise AuthorizationError.new(req.error_code, req.error_comment)
    end
    req.response = {
      transaction_id: req.fields["NUMTRANS"].to_i,
      authorization:  req.fields["AUTORISATION"] == "XXXXXX" ? nil : req.fields["AUTORISATION"].to_i
    }
    if op_code == 56
      req.response[:wallet] = req.fields["PORTEUR"]

      # We now execute debit after authorization-only operation #56
      if opts[:debit]
        sleep 1 # Paybox recommends to wait a few seconds between the authorization and the debit
        debit_authorization(
          amount:         opts[:amount],
          currency:       opts[:currency],
          request_id:     req.request_id,
          transaction_id: req.response[:transaction_id]
        )
      end
    end
    return req
  end

  # Executes a direct debit, without prior authorization.
  #
  # Calls #authorize with { debit: true }.
  def self.debit(opts)
    opts[:debit] = true
    return authorize(opts)
  end

  # Executes a debit on a prior authorization.
  #
  # == Options:
  # * amount:         The decimal amount, e.g. 49.9 for €49.90 (or other currency)
  # * currency:       The currency code, e.g. :EUR
  # * request_id:     The Paybox request ID (NUMAPPEL)
  # * transaction_id: The Paybox transaction ID (NUMTRANS)
  #
  # This will execute a #2 operation.
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request.
  #
  # == Raises:
  # * PayboxDirect::DebitError, if debit fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.debit_authorization(opts)
    raise ArgumentError, "Expecting hash" unless opts.is_a? Hash
    raise ArgumentError, "Expecting `amount` option" unless opts.has_key? :amount
    raise ArgumentError, "Expecting `currency` option" unless opts.has_key? :currency
    raise ArgumentError, "Expecting `request_id` option" unless opts.has_key? :request_id
    raise ArgumentError, "Expecting `transaction_id` option" unless opts.has_key? :transaction_id
    raise ArgumentError, "amount: Expecting Numeric" unless opts[:amount].is_a? Numeric
    raise ArgumentError, "currency: Not supported" unless CURRENCIES.has_key? opts[:currency]
    raise ArgumentError, "request_id: Expecting Fixnum" unless opts[:request_id].is_a? Fixnum
    raise ArgumentError, "transaction_id: Expecting Fixnum" unless opts[:transaction_id].is_a? Fixnum

    req = Request.new({
      "TYPE"     => "00002",
      "MONTANT"  => (opts[:amount].round(2) * 100).round.to_s.rjust(10, "0"),
      "DEVISE"   => CURRENCIES[opts[:currency]].to_s.rjust(3, "0"),
      "NUMAPPEL" => opts[:request_id].to_s.rjust(10, "0"),
      "NUMTRANS" => opts[:transaction_id].to_s.rjust(10, "0")
    })
    req.execute!

    if req.failed?
      raise DebitError.new(req.error_code, req.error_comment)
    end
    return req
  end

  # Cancels an operation if possible.
  #
  # == Options:
  # * amount:     The decimal amount, e.g. 49.9 for €49.90 (or other currency)
  # * currency:   The currency code, e.g. :EUR
  # * ref:        The credit application reference
  # * wallet:     The wallet number (if subscribed)
  # * cc_expire:  The credit card expiration date, e.g. Date.new(2015, 10, 1) (if subscribed)
  # * cc_cvv:     The credit card CVV, e.g. "123"
  # * subscriber: (optional) A subscriber ID
  # * request_id:     The request ID (NUMAPPEL)
  # * transaction_id: The transaction ID (NUMTRANS)
  #
  # This will execute a #55 operation if a subscriber is specified, otherwise
  # a #5 operation.
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request.
  #
  # == Raises:
  # * PayboxDirect::CancelError, if cancellation fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.cancel(opts)
    raise ArgumentError, "Expecting hash" unless opts.is_a? Hash
    raise ArgumentError, "Expecting `amount` option" unless opts.has_key? :amount
    raise ArgumentError, "Expecting `currency` option" unless opts.has_key? :currency
    raise ArgumentError, "Expecting `ref` option" unless opts.has_key? :ref
    raise ArgumentError, "Expecting `cc_cvv` option" unless opts.has_key? :cc_cvv
    raise ArgumentError, "Expecting `request_id` option" unless opts.has_key? :request_id
    raise ArgumentError, "Expecting `transaction_id` option" unless opts.has_key? :transaction_id
    raise ArgumentError, "amount: Expecting Numeric" unless opts[:amount].is_a? Numeric
    raise ArgumentError, "currency: Not supported" unless CURRENCIES.has_key? opts[:currency]
    raise ArgumentError, "cc_expire: Expecting Date" unless opts[:cc_expire].is_a? Date
    raise ArgumentError, "request_id: Expecting Numeric" unless opts[:request_id].is_a? Numeric
    raise ArgumentError, "transaction_id: Expecting Numeric" unless opts[:transaction_id].is_a? Numeric

    if opts.has_key? :subscriber
      raise ArgumentError, "Expecting `wallet` option" unless opts.has_key? :wallet
      raise ArgumentError, "Expecting `cc_expire` option" unless opts.has_key? :cc_expire
      op_code = 55
    else
      raise ArgumentError, "Unexpected `wallet` option" if opts.has_key? :wallet
      op_code = 5
    end

    vars = {
      "TYPE"      => op_code.to_s.rjust(5, "0"),
      "REFERENCE" => @@config.ref_prefix + opts[:ref],
      "MONTANT"   => (opts[:amount].round(2) * 100).round.to_s.rjust(10, "0"),
      "DEVISE"    => CURRENCIES[opts[:currency]].to_s.rjust(3, "0"),
      "DATEVAL"   => opts[:cc_expire].strftime("%m%y"),
      "CVV"       => opts[:cc_cvv],
      "NUMAPPEL"  => opts[:request_id].to_s.rjust(10, "0"),
      "NUMTRANS"  => opts[:transaction_id].to_s.rjust(10, "0")
    }
    if opts.has_key? :subscriber
      vars["PORTEUR"]   = opts[:wallet]
      vars["REFABONNE"] = @@config.ref_prefix + opts[:subscriber]
    end
    req = Request.new(vars)
    req.execute!

    if req.failed?
      raise CancelError.new(req.error_code, req.error_comment)
    end
    return req
  end

  # Executes a refund operation.
  #
  # == Options:
  # * amount:         The decimal amount, e.g. 49.9 for €49.90 (or other currency)
  # * currency:       The currency code, e.g. :EUR
  # * request_id:     The request ID (NUMAPPEL)
  # * transaction_id: The transaction ID (NUMTRANS)
  #
  # This will execute a #14 operation.
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request.
  #
  # == Raises:
  # * PayboxDirect::RefundError, if cancellation fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.refund(opts)
    raise ArgumentError, "Expecting hash" unless opts.is_a? Hash
    raise ArgumentError, "Expecting `amount` option" unless opts.has_key? :amount
    raise ArgumentError, "Expecting `currency` option" unless opts.has_key? :currency
    raise ArgumentError, "Expecting `request_id` option" unless opts.has_key? :request_id
    raise ArgumentError, "Expecting `transaction_id` option" unless opts.has_key? :transaction_id
    raise ArgumentError, "amount: Expecting Numeric" unless opts[:amount].is_a? Numeric
    raise ArgumentError, "currency: Not supported" unless CURRENCIES.has_key? opts[:currency]
    raise ArgumentError, "request_id: Expecting Numeric" unless opts[:request_id].is_a? Numeric
    raise ArgumentError, "transaction_id: Expecting Numeric" unless opts[:transaction_id].is_a? Numeric

    req = Request.new({
      "TYPE"     => "00014",
      "MONTANT"  => (opts[:amount].round(2) * 100).round.to_s.rjust(10, "0"),
      "DEVISE"   => CURRENCIES[opts[:currency]].to_s.rjust(3, "0"),
      "NUMAPPEL" => opts[:request_id].to_s.rjust(10, "0"),
      "NUMTRANS" => opts[:transaction_id].to_s.rjust(10, "0")
    })
    req.execute!

    if req.failed?
      raise RefundError.new(req.error_code, req.error_comment)
    end
    return req
  end

  # Executes a credit operation.
  #
  # == Options:
  # * amount:     The decimal amount, e.g. 49.9 for €49.90 (or other currency)
  # * currency:   The currency code, e.g. :EUR
  # * ref:        The credit application reference
  # * cc_number:  The credit card number, e.g. "1234123412341234" (if not subscribed)
  # * wallet:     The wallet number (if subscribed)
  # * cc_expire:  The credit card expiration date, e.g. Date.new(2015, 10, 1)
  # * cc_cvv:     The credit card CVV, e.g. "123"
  # * subscriber: (optional) A subscriber ID
  #
  # This will execute a #54 operation if a subscriber is specified, otherwise
  # a #4 operation.
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request.
  #
  # == Raises:
  # * PayboxDirect::CreditError, if credit fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.credit(opts)
    raise ArgumentError, "Expecting hash" unless opts.is_a? Hash
    raise ArgumentError, "Expecting `amount` option" unless opts.has_key? :amount
    raise ArgumentError, "Expecting `currency` option" unless opts.has_key? :currency
    raise ArgumentError, "Expecting `ref` option" unless opts.has_key? :ref
    raise ArgumentError, "Expecting `cc_expire` option" unless opts.has_key? :cc_expire
    raise ArgumentError, "Expecting `cc_cvv` option" unless opts.has_key? :cc_cvv
    raise ArgumentError, "amount: Expecting Numeric" unless opts[:amount].is_a? Numeric
    raise ArgumentError, "currency: Not supported" unless CURRENCIES.has_key? opts[:currency]
    raise ArgumentError, "cc_expire: Expecting Date" unless opts[:cc_expire].is_a? Date

    if opts.has_key? :subscriber
      raise ArgumentError, "Expecting `wallet` option" unless opts.has_key? :wallet
      raise ArgumentError, "cc_number: Unexpected when `wallet` provided" if opts.has_key? :cc_number
      op_code = 54
    else
      raise ArgumentError, "Expecting `cc_number` option" unless opts.has_key? :cc_number
      raise ArgumentError, "Unexpected `wallet` option" if opts.has_key? :wallet
      op_code = 4
    end

    vars = {
      "TYPE"      => op_code.to_s.rjust(5, "0"),
      "REFERENCE" => @@config.ref_prefix + opts[:ref],
      "MONTANT"   => (opts[:amount].round(2) * 100).round.to_s.rjust(10, "0"),
      "DEVISE"    => CURRENCIES[opts[:currency]].to_s.rjust(3, "0"),
      "PORTEUR"   => opts.has_key?(:wallet) ? opts[:wallet] : opts[:cc_number].gsub(/[ -.]/, ""),
      "DATEVAL"   => opts[:cc_expire].strftime("%m%y"),
      "CVV"       => opts[:cc_cvv]
    }
    if opts.has_key? :subscriber
      vars["REFABONNE"] = @@config.ref_prefix + opts[:subscriber]
    end
    req = Request.new(vars)
    req.execute!

    if req.failed?
      raise CreditError.new(req.error_code, req.error_comment)
    end
    return req
  end

  # Deletes a subscriber per ID.
  #
  # == Arguments:
  # * id: The subscriber ID (REFABONNE).
  #
  # This will execute a #58 operation.
  #
  # == Returns: (PayboxDirect::Request)
  # The Paybox request.
  #
  # == Raises:
  # * PayboxDirect::DeleteSubscriberError, if deletion fails
  # * PayboxDirect::ServerUnavailableError, if Paybox server is unavailable
  def self.delete_subscriber(id)
    raise ArgumentError, "id: Expecting String" unless id.is_a? String

    req = Request.new({
      "TYPE"      => "00058",
      "REFABONNE" => @@config.ref_prefix + id
    })
    req.execute!
    if req.failed?
      raise DeleteSubscriberError.new(req.error_code, req.error_comment)
    end
    return req
  end
end

require 'paybox_direct/request'
require 'paybox_direct/exceptions'
