require 'net/http'
class Ipn < ActiveRecord::Base
  attr_accessible :data
  belongs_to :payment

  after_create :create_payment

  def date_parsed
    begin
      Date.strptime(self.payment_date, "%H:%M:%S %b %e, %Y %Z")
    rescue
      Date.new
    end
  end

  def self.new_from_dynamic_params(params)
    ipn = Ipn.new()

    ipn.attributes.each do |c|
      unless params[c.first.to_sym].nil?
        ipn[c.first.to_sym] = params[c.first.to_sym]
      end
    end

    return ipn
  end

  # Post back to Paypal to make sure it's valid
  def validate!
    uri = URI.parse('https://www.paypal.com/cgi-bin/webscr?cmd=_notify-validate')

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 60
    http.read_timeout = 60
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.use_ssl = true
    response = http.post(uri.request_uri, self.data,
                         'Content-Length' => "#{self.data.size}",
                         'User-Agent' => "Ruby on Rails"
                       ).body

    unless ["VERIFIED", "INVALID"].include?(response)
      Rails.logger.error "Faulty paypal result: #{response}"
      return false
    end
    unless response == "VERIFIED"
      Rails.logger.error "Invalid IPN: #{response}" 
      Rails.logger.error "Data: #{self.data}"
      return false
    end

    return true
  end

  def link_payment
    create_payment
  end

  private
  def create_payment
    Rails.logger.info "IPN #{self.id}: Attempting to create payment for payer_email: #{self.payer_email}"

    # find user by email, then by payee
    user = User.where("lower(email) = ?", self.payer_email.downcase).first
    user = User.where("lower(payee) = ?", self.payer_email.downcase).first if user.nil? && self.payer_email.present?

    # Only create payments if the IPN matches a member
    if user.present?
      Rails.logger.info "IPN #{self.id}: Found user #{user.id} (#{user.name})"

      # And is a payment (not a cancellation, etc)
      payment_types = ["subscr_payment","send_money"]
      if payment_types.include?(self.txn_type)
        Rails.logger.info "IPN #{self.id}: Transaction type '#{self.txn_type}' is valid"

        # And a member level
        if User.member_levels[self.payment_gross.to_i].present?
          Rails.logger.info "IPN #{self.id}: Payment amount #{self.payment_gross} matches member level"

          payment = Payment.new
          payment.date = Date.strptime(self.payment_date, "%H:%M:%S %b %e, %Y %Z")
          payment.user_id = user.id
          payment.amount = self.payment_gross
          if payment.save
            self.payment_id = payment.id
            self.save!
            Rails.logger.info "IPN #{self.id}: Payment #{payment.id} created successfully for user #{user.id}"
          else
            Rails.logger.error "IPN #{self.id}: Failed to save payment - #{payment.errors.full_messages.first}"
            return [false, "Unable to link payment. Payment error: #{payment.errors.full_messages.first}"]
          end
        else
          Rails.logger.warn "IPN #{self.id}: Payment amount #{self.payment_gross.to_i} doesn't match any member level"
          return [false, "Unable to link payment. Couldn't find membership level '#{self.payment_gross.to_i}'."]
        end
      else
        Rails.logger.warn "IPN #{self.id}: Transaction type '#{self.txn_type}' is not a valid payment type"
        return [false, "Unable to link payment. Transaction is a '#{self.txn_type}' instead of '#{payment_types.inspect}'."]
      end
    else
      Rails.logger.warn "IPN #{self.id}: Could not find user with email or payee matching '#{self.payer_email}'"
      return [false, "Unable to link payment. Couldn't find user/payee '#{self.payer_email}'."]
    end

    return [true]
  end

end
