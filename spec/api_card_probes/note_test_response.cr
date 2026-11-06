require "./probe_support"

response = Amber::Testing::TestResponse.new(200, "{}", HTTP::Headers.new)
consumer = APICardResponseConsumer.new
typeof(consumer.merge_cookie_jar("jar", response)).should eq(Amber::Testing::TestResponse)
typeof(response).should eq(Amber::Testing::TestResponse)
typeof(response.status_code).should eq(Int32)
typeof(response.body).should eq(String)
typeof(response.json).should eq(JSON::Any)
typeof(response.successful?).should eq(Bool)
typeof(APICardProbeRequestHelpers.new.get_response).should eq(Amber::Testing::TestResponse)
