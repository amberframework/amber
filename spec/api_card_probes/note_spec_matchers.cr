require "./probe_support"

nil_value = nil.as(String?)
nil_value.should be_nil
APICardNamedSpecSubject.value.should eq("ok")
