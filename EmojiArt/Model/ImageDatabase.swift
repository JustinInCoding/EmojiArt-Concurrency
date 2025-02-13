/// Copyright (c) 2024 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit

@globalActor actor ImageDatabase {
	static let shared = ImageDatabase()
	let imageLoader = ImageLoader()
	private var storage: DiskStorage!
	private var storedImageIndex = Set<String>()
	
	@MainActor private(set) var onDiskAccess: AsyncStream<Int>?
	private var onDiskAccessContinuation: AsyncStream<Int>.Continuation?
	private var onDiskAccessCounter = 0 {
		didSet {
			onDiskAccessContinuation?.yield(onDiskAccessCounter)
		}
	}
	
	deinit {
		onDiskAccessContinuation?.finish()
	}
	
	func setUp() async throws {
		storage = await DiskStorage()
		for fileURL in try await storage.persistedFiles() {
			storedImageIndex.insert(fileURL.lastPathComponent)
		}
		await imageLoader.setUp()
		let accessStream = AsyncStream<Int> { continuation in
			onDiskAccessContinuation = continuation
		}
		await MainActor.run {
			onDiskAccess = accessStream
		}
	}
	
	func store(image: UIImage, for key: String) async throws {
		guard let data = image.pngData() else {
			throw "Could not save image \(key)"
		}
		let fileName = DiskStorage.fileName(for: key)
		try await storage.write(data, name: fileName)
		storedImageIndex.insert(fileName)
	}
	
	func image(_ key: String) async throws -> UIImage {
		let keys = await imageLoader.cache.keys
		if keys.contains(key) {
			print("In memory cache.")
			return try await imageLoader.image(key)
		}
		do {
			let fileName = DiskStorage.fileName(for: key)
			if !storedImageIndex.contains(fileName) {
				throw "Image not persisted."
			}
			let data = try await storage.read(name: fileName)
			guard let image = UIImage(data: data) else {
				throw "Invalide image data."
			}
			print("In disk cache.")
			onDiskAccessCounter += 1
			await imageLoader.add(image, forKey: key)
			return image
		} catch {
			let image = try await imageLoader.image(key)
			try await store(image: image, for: key)
			return image
		}
	}
	
	func clear() async {
		for name in storedImageIndex {
			try? await storage.remove(name: name)
		}
		storedImageIndex.removeAll()
		onDiskAccessCounter = 0
		print("Cleared disk cache.")
	}
	
	func clearInMemoryAssets() async {
		await imageLoader.clear()
		print("Cleared in-memory cache.")
	}
	
}
