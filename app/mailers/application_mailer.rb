class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SETTLEFLOW_MAIL_FROM", "ops@settleflow.local")
end
