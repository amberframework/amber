require "./probe_support"

describe APICardNamedSpecSubject do
  it "uses the named type directly in Crystal Spec" do
    APICardNamedSpecSubject.value.should eq("ok")
  end
end
