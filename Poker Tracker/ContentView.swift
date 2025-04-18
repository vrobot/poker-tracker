import SwiftUI
import SwiftData
import Foundation
import AVFoundation
import UIKit
// Helper to dismiss keyboard
#if canImport(UIKit)
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

struct ContentView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var txs: [Transaction]
    @Environment(\.modelContext) private var ctx
    @State private var input = ""
    @State private var isBuyIn = true

    private var total: Int { txs.reduce(0) { $0 + $1.amount } }
    
    private func deleteItems(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let tx = txs[index]
                ctx.delete(tx)
            }
        }
    }

    var body: some View {
        NavigationStack {
            // Input area
            VStack(spacing: 16) {
                // Total display
                Text("Total: \(total)")
                    .font(.largeTitle)
                    .foregroundColor(.black)

                // Input row
                HStack {
                    TextField("Amt", text: $input)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Picker("", selection: $isBuyIn) {
                        Text("Buy‑In").tag(true)
                        Text("Exit").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Button("Add") {
                        guard let v = Int(input) else { return }
                        ctx.insert(Transaction(amount: isBuyIn ? -v : v))
                        input = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            }
            .padding()

            // Transaction list
            List {
                ForEach(txs) { tx in
                    NavigationLink(destination: TransactionDetailView(transaction: tx)) {
                        HStack {
                            Text("\(tx.amount > 0 ? "+" : "")\(tx.amount) \(tx.amount > 0 ? "(exit)" : "(buy in)")")
                            Spacer()
                            Text(tx.date, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.plain)
            .accentColor(.black)
        }
    }
}

struct TransactionDetailView: View {
    @Bindable var transaction: Transaction
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var transcriptionInProgress = false
    @State private var errorMessage: String?
    @State private var animatePulse = false

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(transaction.id).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func stopRecordingAndTranscribe() {
        audioRecorder?.stop()
        isRecording = false
        guard let url = audioRecorder?.url else { return }
        transcribeAudio(url: url)
    }

    private func transcribeAudio(url: URL) {
        transcriptionInProgress = true
        errorMessage = nil
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              !apiKey.isEmpty else {
            fatalError("Missing OPENAI_API_KEY in Info.plist")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        // file part
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        data.append(try! Data(contentsOf: url))
        data.append("\r\n".data(using: .utf8)!)

        // model part
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("whisper-1\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: data) { responseData, _, error in
            DispatchQueue.main.async {
                transcriptionInProgress = false
                if let error = error {
                    errorMessage = "Transcription error: \(error.localizedDescription)"
                    return
                }
                guard
                    let responseData = responseData,
                    let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                    let text = json["text"] as? String
                else {
                    errorMessage = "Invalid response"
                    return
                }

                if transaction.notes.isEmpty {
                    transaction.notes = text
                } else {
                    transaction.notes += "\n" + text
                }
            }
        }.resume()
    }

    var body: some View {
        Form {
            Section("Amount & Date") {
                Text("\(transaction.amount > 0 ? "+" : "")\(transaction.amount) \(transaction.amount > 0 ? "(exit)" : "(buy in)")")
                Text(transaction.date, format: .dateTime)
            }

            Section("Notes") {
                TextEditor(text: $transaction.notes)
                    .frame(minHeight: 150)
            }

            Section {
                if let error = errorMessage {
                    Text(error).foregroundColor(.red)
                }
                if transcriptionInProgress {
                    ProgressView("Transcribing…")
                }
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(isRecording ? 0.2 : 0.1))
                        .frame(width: 64, height: 64)
                        .scaleEffect(animatePulse ? 1.2 : 1)
                        .animation(isRecording ?
                            Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                            value: animatePulse
                        )

                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .frame(maxWidth: .infinity, alignment: .center)
                .onTapGesture {
                    if isRecording { stopRecordingAndTranscribe() }
                    else { startRecording() }
                }
            }
        }
        .onTapGesture {
            UIApplication.shared.endEditing()
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Transaction.self, inMemory: true)
}
