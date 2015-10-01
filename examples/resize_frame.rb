require File.join(File.dirname(__FILE__),'helpers','frame2cv')

LogTools::Converter.register "converter resizing frames by a factor of 0.25", Time.now,Orocos.registry do
    conversion "/base/samples/frame/Frame","/base/samples/frame/Frame" do |dst,src|
        mat = src.to_mat
        case src.frame_mode
        when :MODE_BAYER_RGGB
            OpenCV::cv::cvtColor(mat,mat,OpenCV::cv::COLOR_BayerRG2BGR)
        when :MODE_BAYER_BGGR
            OpenCV::cv::cvtColor(mat,mat,OpenCV::cv::COLOR_BayerBG2BGR)
        when :MODE_BAYER_GBRG
            OpenCV::cv::cvtColor(mat,mat,OpenCV::cv::COLOR_BayerGB2BGR)
        when :MODE_BAYER_GRBG
            OpenCV::cv::cvtColor(mat,mat,OpenCV::cv::COLOR_BayerGR2BGR)
        else
        end
        OpenCV::cv::resize(mat,mat,OpenCV::cv::Size.new(),0.25,0.25)
        dst.from_mat(mat)
        dst.time = src.time
        dst
    end
end
