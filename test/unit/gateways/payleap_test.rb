require 'test_helper'

class PayLeapTest < Test::Unit::TestCase
  def setup
    @gateway = PayLeapGateway.new(
                  :login => 'login',
                  :password => 'password',
                  :test => true
               )

    @credit_card = ActiveMerchant::Billing::CreditCard.new(
        :type => "american_express",
        :number => "374255312721002",
        :verification_value => "123",
        :month => "10",
        :year => "2009",
        :first_name => "John",
        :last_name => "Doe"
    )
    
    @amount = 100
    
    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal({:PNRef => "331", :CardNum => "1002", :AuthCode => "562"}, response.authorization)
    assert response.test?
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

 private
  # Place raw successful response from gateway here
  def successful_purchase_response
  	%q<<?xml version="1.0" encoding="utf-8"?>
<Response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://TPISoft.com/SmartPayments/">
  <Result>0</Result>
  <RespMSG>Approved</RespMSG>
  <Message>Approved</Message>
  <AuthCode>562</AuthCode>
  <PNRef>331</PNRef>
  <HostCode />
  <GetAVSResult>0</GetAVSResult>
  <GetAVSResultTXT>Issuer did not perform AVS</GetAVSResultTXT>
  <GetStreetMatchTXT>Service Not Requested</GetStreetMatchTXT>
  <GetZipMatchTXT>Service Not Requested</GetZipMatchTXT>
  <GetCVResult>U</GetCVResult>
  <GetCVResultTXT>Service Not Requested</GetCVResultTXT>
  <GetCommercialCard>False</GetCommercialCard>
  <ExtData>CardType=AMEX</ExtData>
</Response>>
  end
  
  # Place raw failed response from gateway here
  def failed_purchase_response
  	%q<<?xml version="1.0" encoding="utf-8"?>
<Response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://TPISoft.com/SmartPayments/">
  <Result>113</Result>
  <RespMSG>Cannot Exceed Sales Cap</RespMSG>
  <Message>Requested Refund Exceeds Available Refund Amount</Message>
  <AuthCode>Cannot_Exceed_Sales_Cap</AuthCode>
  <PNRef>329</PNRef>
  <GetCommercialCard>False</GetCommercialCard>
  <ExtData>CardType=AMEX</ExtData>
</Response>>
  end
end
