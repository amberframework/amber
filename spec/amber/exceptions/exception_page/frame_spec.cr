require "./spec_helper"

include ExceptionPage::Helpers

describe "Frame parsing" do
  it "returns the correct label" do
    frame = frame_for("usr/crystal-lang/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("crystal")

    frame = frame_for("usr/crystal/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("crystal")

    frame = frame_for("lib/exception_page/spec/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("exception_page")

    frame = frame_for("lib/exception_page/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("exception_page")

    frame = frame_for("lib/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("app")

    frame = frame_for("src/frame_spec.cr:6:7 in '->'")
    label_for_frame(frame).should eq("app")
  end
end

private def frame_for(backtrace_line)
  Backtracer.parse(backtrace_line).frames.first
end
