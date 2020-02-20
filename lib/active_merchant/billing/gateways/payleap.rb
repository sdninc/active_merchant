require "rexml/document"

# http://payleap.com/forum/
# http://www.payleap.com/merchants-faq.html
# AVSResult: https://www.wellsfargo.com/downloads/pdf/biz/merchant/visa_avs.pdf
# CVVResult: http://www.bbbonline.org/eExport/doc/MerchantGuide_cvv2.pdf

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayleapGateway < Gateway
        TEST_URL = 'https://uat.payleap.com/TransactServices.svc/'
        LIVE_URL = 'https://secure1.payleap.com/TransactServices.svc/'
        
        PROCESS_CREDIT_CARD_EP = 'ProcessCreditCard'
        PROCESS_WITH_TOKEN_EP = 'ProcessDebitOrCreditCardWithAccounttoken'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']

      self.money_format = :dollars # float dollars with two decimal places

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :jcb, :diners_club]
      # also: Wright Express, Carte Blanche

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.payleap.com/'

      # The name of the gateway
      self.display_name = 'PayLeap'

      HOST_ERROR = -100
      APPROVED = 0

      CARD_CODE_ERRORS = %w[N S]
      AVS_ERRORS = %w[A E N R W Z]


      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end


      def authorize(money, creditcard, options = {})
        post = {}
        add_invoice(post, options) # InvNum
        add_creditcard(post, creditcard) # CardNum, CVNum, ExpDate, NameOnCard
        add_address(post, creditcard, options) # Street, Zip
        add_customer_data(post, options)

        commit('Auth', money, post) # Amount, TransType, UserName, Password

        # TODO: ExtData?
      end

      def tokenize(creditcard, options = {})
        post = {:ExtData => "<CustomerTokenization>T</CustomerTokenization>"}
        add_creditcard(post, creditcard) # CardNum, CVNum, ExpDate, NameOnCard
        add_address(post, creditcard, options) # Street, Zip

        commit('Tokenize', nil, post)
      end

      def purchase_with_token(money, token)
        post = {
            accounttoken: token,
            CVNum: '',
            ExtData: '<CreditCardOnly>T</CreditCardOnly>',
        }

        commit('Sale', money, post, PROCESS_WITH_TOKEN_EP)
      end

      def purchase(money, creditcard, options = {})# TODO Sale
        post = {}
        add_invoice(post, options)
        add_creditcard(post, creditcard)
        add_address(post, creditcard, options)
        add_customer_data(post, options)

        commit('Sale', money, post)
      end

      def capture(money, auth, options = {})
        post = {:AuthCode => auth[:AuthCode], :PNRef => auth[:PNRef], :CardNum => auth[:CardNum]} rescue {}
        # Contrary to the documentation, PNRef and the last 4 digits of the card
        # number must be included, so auth is a hash containing these.
        # Also, PayLeap is evidently set up in such a way that Force is used for what
        # Capture is generally intended for, performing a ForceCapture in this context.
        commit('Force', money, post)
      end

      def void(auth, options = {})
        post = {:AuthCode => auth[:AuthCode], :PNRef => auth[:PNRef]}
        commit('Void', nil, post)
      end

      def credit(money, auth, options = {})
        #requires!(options, :card_number)

#        post = {:AuthCode => auth[:AuthCode], :PNRef => auth[:PNRef], :CardNum => auth[:CardNum]}
        post = {
            :AuthCode => auth[:AuthCode], :PNRef => auth[:PNRef],
            :CardNum => options[:card].number, :ExpDate => expdate(options[:card])
        }
        #add_invoice(post, options)

        commit('Return', money, post)
      end


     private
      # return credit card expiration date in MMYY format
      def expdate(creditcard)
        month = sprintf("%.2i", creditcard.month)
        year  = sprintf("%.4i", creditcard.year)
        "#{month}#{year[2, 2]}"
      end

      def add_customer_data(post, options)
        if(post[:ExtData] == nil) then post[:ExtData] = "" end
        if(options[:customer] != nil) then post[:ExtData] += "<CustomerID>#{options[:customer]}</CustomerID>" end
      end

      def add_address(post, creditcard, options)
        address = options[:billing_address] || options[:address]
        if(address)
          post[:Street] = "#{address[:address1]} #{address[:address2]} #{address[:city]}, #{address[:state]}"
          post[:Zip]    = address[:zip].to_s
        end # else error?
        # TODO: Add address to ExtData as well?
      end

      def add_invoice(post, options)
        post[:InvNum] = options[:invoice]
        # TODO: :invoice or :order_id?
        # TODO: more invoice detail in ExtData?
      end

      def add_creditcard(post, creditcard)
        post[:CardNum]    = creditcard.number
        if(creditcard.verification_value?)
            post[:CVNum]  = creditcard.verification_value
        end
        post[:ExpDate]    = expdate(creditcard)
        post[:NameOnCard] = creditcard.first_name + " " + creditcard.last_name
      end

      # Parse response data into response hash
      def parse(body)
        response = {}
        xml = REXML::Document.new(body)
        if(!xml.root.nil?)
            log = <<-FOO
            ##### Got response:
            ##### XML:
            #{body}
            ##### end XML
            FOO
            xml.root.elements.each do |node|
              response[node.name.to_sym] = node.text
              log += "\t#{node.name}: #{node.text}\n"
            end
            log += "##### end response"
        else
            log = <<-FOO
            ##### Error: Empty response. Body:"
            #{body}
            ##### end body
            FOO
        end
        $LOG&.debug log
        return response
        # Response keys:
        # "Result", "RespMSG", "Message", "Message1", "Message2"
        # "PNRef", "HostCode", "HostURL", "ReceiptURL"
        # "AuthCode", "GetAVSResult", "GetAVSResultTXT"
        # "GetStreetMatchTXT", "GetZipMatchTXT"
        # "GetCVResult", "GetCVResultTXT"
        # "GetGetOrigResult", "GetCommercialCard", "WorkingKey", "KeyPointer"
        # "InvNum", "CardType", "ExtData"
      end

      # Extract informational message from response.
      def message_from(response)
        if(response[:Result].to_i != APPROVED)
          if(CARD_CODE_ERRORS.include?(response[:GetCVResult]))
            return CVVResult.messages[response[:GetCVResult]]
          elsif(AVS_ERRORS.include?(response[:GetAVSResult]))
            return AVSResult.messages[response[:GetAVSResult]]
          end
        end

        respMsg = ""
        if(!response[:Message].nil?) then respMsg += response[:Message]; end
        if(!response[:Message1].nil?) then respMsg += response[:Message1]; end
        if(!response[:Message2].nil?) then respMsg += response[:Message2]; end
        respMsg
      end

      def commit(action, money, parameters, endpoint=nil)
        if(action != 'Void' && action != 'Tokenize')
            parameters[:Amount] = sprintf("%07.2f", money.to_f)
        end
        action = 'Auth' if action == 'Tokenize'
        parameters[:TransType] = action

        url = ((test?)? TEST_URL : LIVE_URL) + (endpoint ? endpoint : PROCESS_CREDIT_CARD_EP)

        $LOG.debug "Using URL: #{url}"
        $LOG.debug "Start of POST data:"
        $LOG.debug post_data(action, parameters)
        $LOG.debug "End of POST data:"
        data = ssl_post(url, post_data(action, parameters))
        response = parse(data)
        message = message_from(response)

        Response.new((response[:Result].to_i == APPROVED), message, response, {
          :authorization => {
            :AuthCode => response[:AuthCode],
            :CardNum => (parameters[:CardNum] != nil)? parameters[:CardNum][-4, 4] : nil,
            :PNRef => response[:PNRef]
          },
          :avs_result => {:code => response[:GetAVSResult]},
          :cvv_result => response[:GetCVResult],
          :test => @options[:test]
        })
      end

      def post_data(action, parameters = {})
        post = {} # evidently these fields are not optional, only the values are
        post[:UserName] = @options[:login]
        post[:Password] = @options[:password]
        post[:TransType] = ""
        post[:CardNum] = ""
        post[:ExpDate] = ""
        post[:MagData] = ""
        post[:NameOnCard] = ""
        # post[:Amount] = "" # Empty amount breaks tokenizing a card
        post[:InvNum] = ""
        post[:PNRef] = ""
        post[:Zip] = ""
        post[:Street] = ""
        post[:CVNum] = ""
        post[:ExtData] = ""
        # use PostData class?
        request = post.merge(parameters).map {|key, value| "#{key}=#{CGI.escape(value.to_s)}"}.join("&")
        request
      end
    end # class PayLeapGateway
  end # module Billing
end # module ActiveMerchant
