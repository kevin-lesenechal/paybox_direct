# Paybox Direct Ruby API #

The `paybox_direct` gem provides a Ruby interface to the French payment platform
**Paybox** and more specifically their **Paybox Direct** and **Paybox Direct
Plus** products. If you plan to use **Paybox Systems**, this gem won't be of any
help.

## Installation ##

Put this in your `Gemfile`:

    gem 'paybox_direct'

To include all the necessary classes, do:

    require 'paybox_direct'

## Configuration ##

Use `PayboxDirect.config` to configure the default settings of the API like your
Paybox credentials. Example:

    PayboxDirect.config.site = 410555 # Your site number

The available configuration variables are:

 * `site`: (Integer) Your site number, see your Paybox contract;
 * `rank`: (Integer) Your rank number, see your Paybox contract;
 * `login`: (String) Your login, see your Paybox contract;
 * `password`: (String) Your password, see your Paybox contract;
 * `is_prod`: (Boolean) Set to false to use the Paybox test server;
 * `ref_prefix`: (String) A prefix to all references including subscriber IDs;
 * `version`: (Integer) The protocol version, `103` for *Paybox Direct*, `104` for *Paybox Direct Plus*;
 * `activity`: (Integer/nil) The activity code (`ACTIVITE`), see Paybox documentation;
 * `bank`: (Integer/nil) The `ACQUEREUR` variable, let `nil` if you don't have special requirements.

## Usage ##

### Authorization only ###

This call will make an authorization without debit:

    req = PayboxDirect.authorize(
      ref:       "my_app_reference",
      amount:    38.29,
      currency:  :EUR,
      cc_number: "4012-0010-3844-3335", # you may omit the dashes
      cc_expire: Date.new(2016, 10, 1), # the day of month doesn't matter
      cc_cvv:    "123"
    )
    req.response[:request_id]     # => The Paybox request ID (NUMAPPEL)
    req.response[:transaction_id] # => The Paybox transaction ID (NUMTRANS)
    req.response[:authorization]  # => The authorization number, `nil` in dev

In case of failure, this will raise a `PayboxDirect::AuthorizationError`
exception. This exception contains two methods: `code` for the numeric error
code (see documentation) and `comment` for a brief error comment (in French)
returned by Paybox.

### Immediate debit ###

To immediately debit a credit card, use the exact same call than before, just
call the `debit` method instead. This may raise a `DebitError` which inherits
`AuthorizationError`.

### Debit on a prior authorization only ###

After an authorization only, you can make this call to proceed to debit:

    PayboxDirect.debit_authorization(
      amount:         38.29,      # This may be lower than the authorization
      currency:       :EUR,
      request_id:     my_req_id,  # The request ID returned from authorization
      transaction_id: my_trans_id # The transaction ID returned from authorization
    )

Will raise `DebitError` in case of failure.

### Subscribers and wallet codes ###

With *Paybox Direct Plus* you can register subscribers for future operations and
not having to store their credit card credentials. To create a subscriber, you
must make an authorization and/or debit and provide the `subscriber` parameter.
This parameter will contain a unique subscriber ID.

When creating a subscriber, the request will return a **wallet code** which is a
string representing the card number will you will pass to future calls on this
subscriber.

Creation:

    req = PayboxDirect.authorize(
      ref:       "my_app_reference",
      amount:    38.29,
      currency:  :EUR,
      cc_number: "4012-0010-3844-3335",
      cc_expire: Date.new(2016, 10, 1),
      cc_cvv:    "123",
      subscriber: "my_sub_id" # This will create this subscriber
    )
    req.response[:wallet] # => Contains the wallet code to store in DB

To proceed to an authorization or debit on a previously created subscriber,
simply replace the `cc_number` argument with `wallet` and provide the subscriber
ID. Example:

    PayboxDirect.debit(
      ref:        "my_app_reference",
      amount:     38.29,
      currency:   :EUR,
      wallet:     my_wallet_code, # The wallet we got on the subscriber's creation
      cc_expire:  Date.new(2016, 10, 1),
      cc_cvv:     "123",
      subscriber: "my_sub_id" # The subscriber ID previously created
    )

### Refund a payment ###

If you want to refund a user, use the `refund` method with:

 * `amount`;
 * `currency`;
 * `request_id`;
 * `transaction_id`.

It may raise `RefundError`, which is clearly possible if the debit you want to
refund wasn't sent to bank yet. The `refund` operation can only apply to
definitive payments. Therefor, you should try to **cancel** the operation (see
below) before refunding.

### Cancel an operation ###

Almost all payment operations can be cancelled before they are transmitted to
the bank and become definitive. Use the `cancel` with these options:

 * `amount`;
 * `currency`;
 * `ref`;
 * `cc_number` or `wallet`;
 * `cc_expire`;
 * `cc_cvv`;
 * `subscriber` (optional, only if on a subscriber);
 * `request_id`;
 * `transaction_id`.

In case of failures, it raises `CancelError`.

### Credits ###

You can credit a user using the `credit` method, this works the same than debits
including with subscribers. It may raise `CreditError`.
