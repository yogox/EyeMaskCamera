//
//  ContentView.swift
//  EyeMaskCamera
//
//  Created by yogox on 2021/06/02.
//

import SwiftUI
import AVFoundation
import Vision

extension AVCaptureDevice.Position: CaseIterable {
    public static var allCases: [AVCaptureDevice.Position] {
        return [.front, .back]
    }
    
    mutating func toggle() {
        self = self == .front ? .back : .front
    }
}
typealias CameraPosition = AVCaptureDevice.Position

extension CGRect {
    func converted(to size: CGSize) -> CGRect {
        return CGRect(x: self.minX * size.width,
                      y: self.minY * size.height,
                      width: self.width * size.width,
                      height: self.height * size.height)
    }
}

class EyeMaskCamera: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    @Published var image: UIImage?
    @Published var previewLayer:[CameraPosition:AVCaptureVideoPreviewLayer] = [:]
    private var captureDevice:AVCaptureDevice!
    private var captureSession:[CameraPosition:AVCaptureSession] = [:]
    private var dataOutput:[CameraPosition:AVCapturePhotoOutput] = [:]
    private var currentCameraPosition:CameraPosition
    private let semaphore = DispatchSemaphore(value: 0)
    
    override init() {
        currentCameraPosition = .back
        super.init()
        for cameraPosition in CameraPosition.allCases {
            previewLayer[cameraPosition] = AVCaptureVideoPreviewLayer()
            captureSession[cameraPosition] = AVCaptureSession()
            setupSession(cameraPosition: cameraPosition)
        }
        captureSession[currentCameraPosition]?.startRunning()
    }
    
    private func setupDevice(cameraPosition: CameraPosition = .back) {
        if let availableDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: cameraPosition).devices.first {
            captureDevice = availableDevice
        }
    }
    
    private func setupSession(cameraPosition: CameraPosition = .back) {
        setupDevice(cameraPosition: cameraPosition)
        
        let captureSession = self.captureSession[cameraPosition]!
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(captureDeviceInput)
        } catch {
            print(error.localizedDescription)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer[cameraPosition] = previewLayer
        
        dataOutput[cameraPosition] = AVCapturePhotoOutput()
        guard let photoOutput = dataOutput[cameraPosition] else { return }
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            
//            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        }
        
        captureSession.commitConfiguration()
    }
    
    func switchCamera() {
        captureSession[currentCameraPosition]?.stopRunning()
        currentCameraPosition.toggle()
        captureSession[currentCameraPosition]?.startRunning()
    }
    
    func takePhoto() {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
//        settings.isDepthDataDeliveryEnabled = true
        
        dataOutput[currentCameraPosition]?.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // 元写真を取得
        guard let imageData = photo.fileDataRepresentation(), let ciImage = CIImage(data: imageData) else {return}
        var photoImage = ciImage
        
        // 画像の向きを決め打ち修正
        photoImage = photoImage.oriented(.right)
        // Imageクラスでも描画されるようにCGImage経由でUIImageに変換
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(photoImage, from: photoImage.extent)
        
        if let cgImage = cgImage {
            let cgContext = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: cgImage.bytesPerRow,
                space: cgImage.colorSpace!,
                bitmapInfo: cgImage.bitmapInfo.rawValue
            )
            let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
            cgContext?.draw(cgImage, in: imageRect)
            cgContext?.setLineWidth(4.0)
            cgContext?.setStrokeColor(UIColor.green.cgColor)
            let cgSize = CGSize(width: cgImage.width, height: cgImage.height)
            print(cgSize)
            
//            let request = VNDetectFaceRectanglesRequest { (request, error) in
            let request = VNDetectFaceLandmarksRequest { (request, error) in
                guard let results = request.results as? [VNFaceObservation] else {
                    return
                }
                
                for observation in results {
                    print(observation.boundingBox)
                    print(observation.boundingBox.converted(to: cgSize))
                    cgContext?.stroke(observation.boundingBox.converted(to: cgSize))
//                    print(observation.landmarks!)
                    
                    print("rightEyebrow:")
//                    print(observation.landmarks?.rightEyebrow?.normalizedPoints)
                    print(observation.landmarks?.rightEyebrow?.pointsInImage(imageSize: cgSize))
                    print("leftEyebrow:")
//                    print(observation.landmarks?.leftEyebrow?.normalizedPoints)
                    print(observation.landmarks?.leftEyebrow?.pointsInImage(imageSize: cgSize))

                    cgContext?.setStrokeColor(UIColor.blue.cgColor)
                    cgContext?.addLines(between: (observation.landmarks?.leftEyebrow?.pointsInImage(imageSize: cgSize))!)
                    cgContext?.addLines(between: (observation.landmarks?.rightEyebrow?.pointsInImage(imageSize: cgSize))!)
                    cgContext?.strokePath()
                    
                    print("rightEye:")
//                    print(observation.landmarks?.rightEye?.normalizedPoints)
                    print(observation.landmarks?.rightEye?.pointsInImage(imageSize: cgSize))
                    print("leftEye:")
//                    print(observation.landmarks?.leftEye?.normalizedPoints)
                    print(observation.landmarks?.leftEye?.pointsInImage(imageSize: cgSize))

                    cgContext?.setStrokeColor(UIColor.red.cgColor)
                    cgContext?.addLines(between: (observation.landmarks?.leftEye?.pointsInImage(imageSize: cgSize))!)
                    cgContext?.addLines(between: (observation.landmarks?.rightEye?.pointsInImage(imageSize: cgSize))!)
                    cgContext?.strokePath()
                    
                    print("angle:")
                    print(observation.roll!)
                    print(observation.yaw!)
                    
//                    let landmarkReauest = VNDetectFaceLandmarksRequest { (request, error) in
//                        guard let results = request.results as? [VNFaceObservation] else {
//                            return
//                        }
//
//                        print(results.count)
//
//                        for observation in results {
//                            print(observation.landmarks)
//                        }
//                    }
//
//                    landmarkReauest.inputFaceObservations = [observation]
//                    let landmarkHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
//                    try? landmarkHandler.perform([landmarkReauest])
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            
            let newImage = cgContext?.makeImage()
//            self.image = UIImage(cgImage: cgImage)
            self.image = UIImage(cgImage: newImage!)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // 撮影処理中はプレビューを止める
        stopSession()
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?) {
        semaphore.signal()
    }
    
    func waitPhoto() {
        semaphore.wait()
    }
    
    func stopSession() {
        if let session = captureSession[currentCameraPosition], session.isRunning == true {
            session.stopRunning()
        }
    }

    func restartSession() {
        if let session = captureSession[currentCameraPosition], session.isRunning == false {
            session.startRunning()
        }
    }

    func clearImage() {
        image = nil
    }
}

struct CALayerView: UIViewControllerRepresentable {
    var caLayer:AVCaptureVideoPreviewLayer
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<CALayerView>) -> UIViewController {
        let viewController = UIViewController()
        
        let width = viewController.view.frame.width
        let height = viewController.view.frame.height
        let previewHeight = width * 4 / 3
        
        caLayer.videoGravity = .resizeAspect
        viewController.view.layer.addSublayer(caLayer)
        caLayer.frame = viewController.view.frame
        caLayer.position = CGPoint(x: width/2, y: previewHeight/2 + (height - previewHeight - 75)/3 )
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: UIViewControllerRepresentableContext<CALayerView>) {
    }
}

enum Views {
    case transferPhoto
}

struct ContentView: View {
    @ObservedObject var segmentationCamera = EyeMaskCamera()
    @State private var flipped = false
    @State private var angle:Double = 0
    @State private var selection:Views? = .none
    // アラート表示
    @State private var showAlert = false
    // 撮影・処理中のボタン制御
    @State private var buttonGuard = false
    // プログレスバーの表示
    @State private var inProgress = false

    func enableButtonWithPreview() {
        enableButton()
        self.segmentationCamera.restartSession()
    }

    func disableButtonWithPreview() {
        disableButton()
        self.segmentationCamera.stopSession()
    }
    
    func enableButton() {
        buttonGuard = false
    }

    func disableButton() {
        buttonGuard = true
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    ZStack() {
                        CALayerView(caLayer: self.segmentationCamera.previewLayer[.front]!).opacity(self.flipped ? 1.0 : 0.0)
                        CALayerView(caLayer: self.segmentationCamera.previewLayer[.back]!).opacity(self.flipped ? 0.0 : 1.0)
                    }
                    .modifier(FlipEffect(flipped: self.$flipped, angle: self.angle, axis: (x: 0, y: 1)))
                    
                    VStack {
                        
                        Spacer()
                        
                        Color.clear
                            .frame(width: geometry.size.width, height: geometry.size.width / 3 * 4)
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            
                            Color.clear
                                .frame(width: 40, height: 40)
                            
                            Spacer()
                            
                            Button(action: {
                                disableButton()
                                // 前回の画像を消去
                                self.segmentationCamera.clearImage()
                                
                                self.segmentationCamera.takePhoto()

                                DispatchQueue.global(qos: .userInitiated).async {
                                    inProgress = true

                                    // セマフォで撮影完了を待つ
                                    self.segmentationCamera.waitPhoto()
                                    if self.segmentationCamera.image != nil {
                                        // 画像が設定されている＝SemanticSegmentation完了なら画面遷移
                                        self.selection = .transferPhoto
                                    } else {
                                        // SemanticSegmentationできなかったら警告
                                        self.showAlert = true
                                    }
                                    
                                    inProgress = false
                                }

                            }) {
                                Image(systemName: "camera.circle.fill")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 75, height: 75, alignment: .center)
                                    .foregroundColor(Color.white)
                            }
                            // ボタンを制御可能にする
                            .disabled(buttonGuard)
                            
                            Spacer()
                            
                            Button(action: {
                                self.segmentationCamera.switchCamera()
                                withAnimation(nil) {
                                    if self.angle >= 360 {
                                        self.angle = self.angle.truncatingRemainder(dividingBy: 360)
                                    }
                                }
                                withAnimation(Animation.easeIn(duration: 0.5)) {
                                    self.angle += 180
                                }
                            }) {
                                Image(systemName: "camera.rotate")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40, alignment: .center)
                                    .foregroundColor(Color.white)
                            }
                            // ボタンを制御可能にする
                            .disabled(buttonGuard)
                            
                            Spacer()
                        }
                        NavigationLink(destination: TransferPhotoView(segmentationCamera: self.segmentationCamera, selection: self.$selection, buttonGuard: self.$buttonGuard
                            ),
                                       tag:Views.transferPhoto,
                                       selection:self.$selection) {
                                        EmptyView()
                        }
                        
                        Spacer()
                        
                    }
                    .navigationBarTitle(/*@START_MENU_TOKEN@*/"Navigation Bar"/*@END_MENU_TOKEN@*/)
                    .navigationBarHidden(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    .alert(isPresented: $showAlert) {
                        Alert(title: Text("Alert"),
                              message: Text("No object with segmentation"),
                              dismissButton: .default(Text("OK"), action: {
                                enableButtonWithPreview()
                              })
                        )
                    }
                    
                    // 写真撮影中のプログレス表示
                    ProgressView("Caputring Now").opacity(self.inProgress ? 1.0 : 0.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5, anchor: .center)
                        .shadow(color: .secondary, radius: 2)

                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color.black)
                
            }
        }
    }
}

struct FlipEffect: GeometryEffect {
    
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    
    @Binding var flipped: Bool
    var angle: Double
    let axis: (x: CGFloat, y: CGFloat)
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        
        DispatchQueue.main.async {
            self.flipped = self.angle >= 90 && self.angle < 270
        }
        
        let tweakedAngle = flipped ? -180 + angle : angle
        let a = CGFloat(Angle(degrees: tweakedAngle).radians)
        
        var transform3d = CATransform3DIdentity;
        transform3d.m34 = -1/max(size.width, size.height)
        
        transform3d = CATransform3DRotate(transform3d, a, axis.x, axis.y, 0)
        transform3d = CATransform3DTranslate(transform3d, -size.width/2.0, -size.height/2.0, 0)
        
        let affineTransform = ProjectionTransform(CGAffineTransform(translationX: size.width/2.0, y: size.height / 2.0))
        
        return ProjectionTransform(transform3d).concatenating(affineTransform)
    }
}

struct photoView: View {
    @ObservedObject var segmentationCamera: EyeMaskCamera
    
    var body: some View {
        VStack {
            if self.segmentationCamera.image != nil {
                Image(uiImage: self.segmentationCamera.image!)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.black)
            }
        }
    }
}

struct TransferPhotoView: View {
    @ObservedObject var segmentationCamera: EyeMaskCamera
    @Binding var selection:Views?
    @Binding var buttonGuard:Bool

    func enableButtonWithPreview() {
        enableButton()
        self.segmentationCamera.restartSession()
    }

    func disableButtonWithPreview() {
        disableButton()
        self.segmentationCamera.stopSession()
    }
    
    func enableButton() {
        buttonGuard = false
    }

    func disableButton() {
        buttonGuard = true
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            GeometryReader { geometry in
                photoView(segmentationCamera: self.segmentationCamera)
                    .frame(alignment: .center)
                    .border(Color.white, width:1)
                    .background(Color.black)
            }
            
            Spacer()
            
            HStack {
                Button(action: {
                    self.segmentationCamera.clearImage()
                    enableButtonWithPreview()
                    self.selection = .none
                }) {
                    Text("Back")
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/)
        .navigationBarTitle("Image")
        .navigationBarHidden(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
