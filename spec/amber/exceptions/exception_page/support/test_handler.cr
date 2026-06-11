class TestHandler
  include HTTP::Handler

  def call(context)
    case context.request.resource
    when "/favicon.ico"
      context.response.print ""
    when "/multiline-exception"
      begin
        raise CustomException.new("Something went very wrong\nBut wait, there's more!")
      rescue e : CustomException
        context.response.content_type = "text/html"
        context.response.print MyApp::ExceptionPage.new context, e
      end
    else
      begin
        raise CustomException.new("Something went very wrong")
      rescue e : CustomException
        context.response.content_type = "text/html"
        context.response.print MyApp::ExceptionPage.new context, e
      end
    end
  end
end

class CustomException < Exception
end
