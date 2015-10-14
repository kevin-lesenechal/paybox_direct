# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

module PayboxDirect
  class PayboxRequestError < StandardError
    attr_reader :request, :request_id, :code, :comment

    def initialize(request)
      @request    = request
      @request_id = request.request_id
      @code       = request.error_code
      @comment    = request.error_comment
      super("#{@code.to_s.rjust(5, "0")}: #{@comment} (req. ##{@request_id})")
    end

    def may_retry?
      return [105, 151, 157].include? @code
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
