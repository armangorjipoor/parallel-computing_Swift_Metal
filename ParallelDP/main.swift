//
//  main.swift
//  ParallelDP
//
//  Created by Jiheng Zhang on 1/1/2016.
//  Copyright © 2016 verse. All rights reserved.
//

import Foundation
import MetalKit

// parameter only needed by the host
let numPeriods = 5  // periods
// parameters needed by both the host and the device
let K = 8  // capacity
let L = 4  // dimension

let salvageValue: Float = 1.5
let holdingCost: Float = 1.11
let orderCost: Float = 1
let desposalCost: Float = 1
let discountRate: Float = 0.95
let price: Float = 1.5


// hardcoded to the following number
// Need to understand more about threadExecutionWidth for optimal config
let threadExecutionWidth = 128

// parameters needs to be transmitted to device
let paramemterVector: [Float] = [
    Float(K),
    Float(L),
    salvageValue,
    holdingCost,
    orderCost,
    desposalCost,
    discountRate,
    price
]

// basic calcuation of buffer
let numberOfStates = Int(pow(Double(K), Double(L)))
let unitSize = sizeof(Float)
let resultBufferSize = numberOfStates*unitSize

// basic calculation of device related parameter
let numThreadsPerGroup = MTLSize(width:threadExecutionWidth,height:1,depth:1)
// the following to be deleted
let numGroups = MTLSize(width:(numberOfStates+threadExecutionWidth-1)/threadExecutionWidth, height:1, depth:1)

// Initialize Metal
// Get the default device, which is the same as the one monitor is using
var device: MTLDevice! = MTLCreateSystemDefaultDevice()
// In the following, choose the device NOT used by monitor
let devices: [MTLDevice] = MTLCopyAllDevices()
for metalDevice: MTLDevice in devices {
    if metalDevice.headless == true {
        device = metalDevice
    }
}
// exit with an error message if all devices are used by monitor
//if !device.headless {
//    print("no dedicated device found")
//    exit(1)
//}

// Build command queue
var commandQueue: MTLCommandQueue! = device.newCommandQueue()

// Allocate memory on device
let resourceOption = MTLResourceOptions()
var buffer:[MTLBuffer] = [
    device.newBufferWithLength(resultBufferSize, options: resourceOption),
    device.newBufferWithLength(resultBufferSize, options: resourceOption)
]

// Get functions from Shaders and add to MTL library
var defaultLibrary: MTLLibrary! = device.newDefaultLibrary()
let initDP = defaultLibrary.newFunctionWithName("initialize")
let pipelineFilterInit = try device.newComputePipelineStateWithFunction(initDP!)
let iterateDP = defaultLibrary.newFunctionWithName("iterate")
let pipelineFilterIterate = try device.newComputePipelineStateWithFunction(iterateDP!)

// Initialize

for l: Int in 1...L {
    var batchSize: Int = 1
    var batchNum: Int = 2
    if l>0 {
        batchSize = Int(pow(Float(K),Float(l-1)))
        batchNum = K
    }

    let numGroupsBatch = MTLSize(width:(batchSize+threadExecutionWidth-1)/threadExecutionWidth, height:1, depth:1)
    print(batchSize)
    for batchIndex: Int in 1..<batchNum {
        
        print(numGroupsBatch)

        // also transmit the batchSize to reduce computation load at device
        let dispatchIterator: [Float] = [Float(batchSize), Float(batchIndex)]
        // this way seems complicated, but parameterVector is immutable for security 
        let transmitVector = dispatchIterator+paramemterVector
        var transmitBuffer:MTLBuffer = device.newBufferWithBytes(transmitVector, length: unitSize*transmitVector.count, options: resourceOption)

        var commandBufferInitDP: MTLCommandBuffer! = commandQueue.commandBuffer()
        var encoderInitDP = commandBufferInitDP.computeCommandEncoder()
        encoderInitDP.setComputePipelineState(pipelineFilterInit)
        // offset is very important
        encoderInitDP.setBuffer(buffer[0], offset: 0, atIndex: 1)
        encoderInitDP.setBuffer(transmitBuffer, offset: 0, atIndex: 0)
        encoderInitDP.dispatchThreadgroups(numGroupsBatch, threadsPerThreadgroup: numThreadsPerGroup)
        encoderInitDP.endEncoding()
        commandBufferInitDP.commit()
        commandBufferInitDP.waitUntilCompleted()
        
    }
}

// Iterate T periods
// It's import that t starts from 0%2=0, since we start with buffer[0]
for t in 0..<numPeriods {
    
    var commandBufferIterateDP: MTLCommandBuffer! = commandQueue.commandBuffer()
    var encoderIterateDP = commandBufferIterateDP.computeCommandEncoder()

    encoderIterateDP.setComputePipelineState(pipelineFilterIterate)
    
//    encoderIterateDP.setBuffer(parameterBuffer, offset: 0, atIndex: 0)
    encoderIterateDP.setBuffer(buffer[t%2], offset: 0, atIndex: 1)
    encoderIterateDP.setBuffer(buffer[(t+1)%2], offset: 0, atIndex: 2)
    
    encoderIterateDP.dispatchThreadgroups(numGroups, threadsPerThreadgroup: numThreadsPerGroup)
    encoderIterateDP.endEncoding()
    commandBufferIterateDP.commit()
    commandBufferIterateDP.waitUntilCompleted()

}

// Get data fro device
var data = NSData(bytesNoCopy: buffer[numPeriods%2].contents(), length: resultBufferSize, freeWhenDone: false)
var finalResultArray = [Float](count: numberOfStates, repeatedValue: 0)
data.getBytes(&finalResultArray, length:resultBufferSize)

print(finalResultArray)

