//
//  BinarySTLParser.swift
//  3dVisor
//
//  Created by Victor Alonso on 10/12/2018.
//  Copyright © 2018 Global DPI. All rights reserved.
//

import Foundation
import SceneKit

public enum BinarySTLParser {
    public enum STLError: Error {
        case fileTooSmall(size: Int)
        case unexpectedFileSize(expected: Int, actual: Int)
        case triangleCountMismatch(diff: Int)
    }
    
    public enum UnitScale: Float {
        case meter = 1.0
        case millimeter = 0.001
    }
    
    public static func createNodeFromSTL(at url: URL,
                                         unit scale: UnitScale = .meter,
                                         correctFor3DPrint: Bool = true) throws -> SCNNode
    {
        let fileData = try Data(contentsOf: url, options: .alwaysMapped) // can cause rethrow
        guard fileData.count > 84 else {
            throw STLError.fileTooSmall(size: fileData.count)
        }
        
        let name = String(data: fileData.subdata(in: 0..<80), encoding: .ascii)
        let triangleTarget: UInt32 = fileData.scanValue(start: 80, length: 4)
        let triangleBytes = MemoryLayout<Triangle>.size
        let expectedFileSize = 84 + triangleBytes * Int(triangleTarget)
        guard fileData.count == expectedFileSize else {
            throw STLError.unexpectedFileSize(expected: expectedFileSize, actual: fileData.count)
        }
        
        var normals = Data()
        var vertices = Data()
        var trianglesCounted: Int = 0
        for index in stride(from: 84, to: fileData.count, by: triangleBytes) {
            trianglesCounted += 1
            
            var triangleData = fileData.subdata(in: index..<index+triangleBytes)
            var triangle: Triangle = triangleData.withUnsafeMutableBytes { $0.pointee }
            
            let normalData = triangle.normal.unsafeData()
            normals.append(normalData)
            normals.append(normalData)
            normals.append(normalData)
            
            vertices.append(triangle.v1.unsafeData())
            vertices.append(triangle.v2.unsafeData())
            vertices.append(triangle.v3.unsafeData())
        }
        
        guard triangleTarget == trianglesCounted else {
            throw STLError.triangleCountMismatch(diff: Int(triangleTarget) - trianglesCounted)
        }
        
        let vertexSource = SCNGeometrySource(data: vertices,
                                             semantic: .vertex,
                                             vectorCount: trianglesCounted * 3,
                                             usesFloatComponents: true,
                                             componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0,
                                             dataStride: MemoryLayout<SCNVector3>.size)
        
        let normalSource = SCNGeometrySource(data: normals,
                                             semantic: .normal,
                                             vectorCount: trianglesCounted * 3,
                                             usesFloatComponents: true,
                                             componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0,
                                             dataStride: MemoryLayout<SCNVector3>.size)
        
        // The SCNGeometryElement accepts `nil` as a value for the index-data, and will then generate a list
        // of auto incrementing indices. It still requires a number of bytes used for the index, whether it
        // is actually used is unknown to me.
        let use8BitIndices = MemoryLayout<UInt8>.size
        let countedTriangles = SCNGeometryElement(data: nil,
                                                  primitiveType: .triangles,
                                                  primitiveCount: trianglesCounted,
                                                  bytesPerIndex: use8BitIndices)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [countedTriangles])
        let geometryNode = SCNNode(geometry: geometry)
        
        var geometryTransform = SCNMatrix4Identity
        
        if correctFor3DPrint {
            // Rotates the x-axis by 90º to correct for how STLs are (typically) used in 3D printing:
            geometryTransform = SCNMatrix4Rotate(geometryTransform, Float.pi / 2, -1, 0, 0)
        }
        
        let scaleFactor = scale.rawValue
        if scaleFactor != 1.0 {
            // ARKit interprets a SCNVector3's units as corresponding to 'meters', where regular SceneKit
            // visualizations 'feel' a lot smaller, and a model of 25 units high easily fits a default view.
            // In 3D printing, it's more common to interpret the units as millimeters, so STLs made for 3D
            // printing need to be scaled down to appear 'right' in an augmented reality context:
            geometryTransform = SCNMatrix4Scale(geometryTransform, scaleFactor, scaleFactor, scaleFactor)
        }
        
        geometryNode.transform = geometryTransform
        
        let modelNode = SCNNode()
        modelNode.addChildNode(geometryNode)
        modelNode.name = name
        
        return modelNode
    }
}

// The layout of this Triangle struct corresponds with the layout of bytes in the STL spec,
// as described at: http://www.fabbers.com/tech/STL_Format#Sct_binary
private struct Triangle {
    var normal: SCNVector3
    var v1: SCNVector3
    var v2: SCNVector3
    var v3: SCNVector3
    var attributes: UInt16
}

private extension SCNVector3 {
    mutating func unsafeData() -> Data {
        return Data(buffer: UnsafeBufferPointer(start: &self, count: 1))
    }
}

private extension Data {
    func scanValue<T>(start: Int, length: Int) -> T {
        return self.subdata(in: start..<start+length).withUnsafeBytes { $0.pointee }
    }
}
