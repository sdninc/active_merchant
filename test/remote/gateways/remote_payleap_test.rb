require 'test_helper'

# Test cards:
# MasterCard: 5000300020003003
#       Visa: 4005550000000019
#   Discover: 60011111111111117
#     Diners: 36999999999999
#       AMEX: 374255312721002

class RemotePayLeapTest < Test::Unit::TestCase
  
  def setup
    ActiveMerchant::Billing::Base.mode = :test
    @gateway = PayLeapGateway.new(fixtures(:payleap))
    
    @amount = 104
    @credit_card = ActiveMerchant::Billing::CreditCard.new(
        :type => "american_express",
        :number => "374255312721002",
        :verification_value => "123",
        :month => "10",
        :year => "2009",
        :first_name => "John",
        :last_name => "Doe"
    )

    @declined_card = ActiveMerchant::Billing::CreditCard.new(
        :type => "american_express",
        :number => "374255312721003",
        :verification_value => "123",
        :month => "10",
        :year => "2009",
        :first_name => "John",
        :last_name => "Doe"
    )
    
    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end
  
  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
#    assert_equal 'REPLACE WITH FAILED PURCHASE MESSAGE', response.message
  end

  def test_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'Approved', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
#    assert_equal 'REPLACE WITH GATEWAY FAILURE MESSAGE', response.message
  end

  def test_invalid_login
    gateway = PayLeapGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
#    assert_equal 'REPLACE WITH FAILURE MESSAGE', response.message
  end
end
