class TwilioTextMessenger
    attr_reader :phone_number
    attr_reader :message

    def initialize(phone_number, message)
        @phone_number = phone_number
        @message = message
    end
  
    def call
        client = Twilio::REST::Client.new
        begin
            client.messages.create({
                from: ENV['TWILIO_PHONE_NUMBER'],
                to: phone_number,
                body: message
            })
        rescue
        end
    end
end