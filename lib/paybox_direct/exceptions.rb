# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

module PayboxDirect
  class PayboxRequestError < StandardError
    attr_reader :code, :comment

    def initialize(code, comment)
      super("#{code.to_s.rjust(5, "0")}: #{comment}")
      @code    = code
      @comment = comment
    end
  end

  class AuthorizationError < PayboxRequestError; end
  class DebitError < AuthorizationError; end
  class CancelError < PayboxRequestError; end
  class RefundError < PayboxRequestError; end
  class CreditError < PayboxRequestError; end
  class DeleteSubscriberError < PayboxRequestError; end
  class ServerUnavailableError < StandardError; end
end
