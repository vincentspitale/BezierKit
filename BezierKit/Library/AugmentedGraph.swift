//
//  AugmentedGraph.swift
//  BezierKit
//
//  Created by Holmes Futrell on 8/28/18.
//  Copyright © 2018 Holmes Futrell. All rights reserved.
//

import CoreGraphics

internal class PathLinkedListRepresentation {
    
    private var lists: [[Vertex]] = []
    private let path: Path
    
    private func insertIntersectionVertex(_ v: Vertex, replacingVertexAtStartOfElementIndex elementIndex: Int, inList list: inout [Vertex]) {
        assert(v.isIntersection)
        let r = list[elementIndex]
        // insert v in the list
        v.setPreviousVertex(r.previous)
        v.setNextVertex(r.next, transition: r.nextTransition)
        v.previous.setNextVertex(v, transition: v.previous.nextTransition)
        v.next.setPreviousVertex(v)
        // replace the list pointer with v
        list[elementIndex] = v
    }
    
    private func insertIntersectionVertex(_ v: Vertex, between start: Vertex, and end: Vertex, at t: CGFloat, for element: BezierCurve, inList list: inout [Vertex]) {
        assert(start !== end)
        assert(v.isIntersection)
        v.splitInfo = Vertex.SplitInfo(t: t)
        let t0: CGFloat = (start.splitInfo != nil) ? start.splitInfo!.t : 0.0
        let t1: CGFloat = (end.splitInfo != nil) ? end.splitInfo!.t : 1.0
        // locate the element for the vertex transitions
        /*
         TODO: this code assumes t0 < t < t1, which could definitely be false if there are multiple intersections against the same element at the same point
         in the least we need a unit test for that case
         */
        let element1 = element.split(from: t0, to: t)
        let element2 = element.split(from: t, to: t1)
        // insert the vertex into the linked list
        v.setPreviousVertex(start)
        v.setNextVertex(end, transition: VertexTransition(curve: element2))
        start.setNextVertex(v, transition: VertexTransition(curve: element1))
        end.setPreviousVertex(v)
    }
    
    internal func insertIntersectionVertex(_ v: Vertex, at location: IndexedPathLocation) {
        
        assert(v.isIntersection)
        
        var list = self.lists[location.componentIndex]
        
        if location.t == 0 {
            // this vertex needs to replace the start vertex of the element
            insertIntersectionVertex(v, replacingVertexAtStartOfElementIndex: location.elementIndex, inList: &list)
        }
        else if location.t == 1 {
            // this vertex needs to replace the end vertex of the element
            insertIntersectionVertex(v, replacingVertexAtStartOfElementIndex: Utils.mod(location.elementIndex+1, list.count), inList: &list)
        }
        else {
            var start = list[location.elementIndex]
            while (start.next.splitInfo != nil) && start.next.splitInfo!.t < location.t {
                start = start.next
            }
            var end = start.next!
            while (end.splitInfo != nil) && end.splitInfo!.t < location.t {
                assert(end !== list[location.elementIndex+1])
                end = end.next
            }
            insertIntersectionVertex(v, between: start, and: end, at: location.t, for: path.element(at: location), inList: &list)
        }
        self.lists[location.componentIndex] = list
    }

    private func createListFor(component: PathComponent) -> [Vertex] {
        guard component.curves.count > 0 else {
            return []
        }
        assert(component.curves.first!.startingPoint == component.curves.last!.endingPoint, "this method assumes component is closed!")
        var elements: [Vertex] = [] // elements[i] is the first vertex of curves[i]
        let firstPoint: CGPoint = component.curves.first!.startingPoint
        let firstVertex = Vertex(location: firstPoint, isIntersection: false)
        elements.append(firstVertex)
        var lastVertex = firstVertex
        for i in 1..<component.curves.count {
            let v = Vertex(location: component.curves[i].startingPoint, isIntersection: false)
            elements.append(v)
            let curveForTransition = component.curves[i-1]
            // set the forwards reference for starting vertex of curve i-1
            lastVertex.setNextVertex(v, transition: VertexTransition(curve: curveForTransition))
            // set the backwards reference for starting vertex of curve i
            v.setPreviousVertex(lastVertex)
            // point previous at v for the next iteration
            lastVertex = v
        }
        // connect the forward reference of the last vertex to the first vertex
        let lastCurve = component.curves.last!
        lastVertex.setNextVertex(firstVertex, transition: VertexTransition(curve: lastCurve))
        // connect the backward reference of the first vertex to the last vertex
        firstVertex.setPreviousVertex(lastVertex)
        // return list of vertexes that point to the start of each element
        return elements
    }
    
    init(_ p: Path) {
        self.path = p
        self.lists = p.subpaths.map { self.createListFor(component: $0) }
    }
    
    fileprivate func markEntryExit(_ path: Path, _ nonCrossingComponents: inout [PathComponent]) {
        for i in 0..<lists.count {
            var hasCrossing: Bool = false
            self.forEachVertexInComponent(atIndex: i) { v in
                guard v.isIntersection else {
                    return
                }
                let previous = v.emitPrevious()
                let next = v.emitNext()
                let wasInside = path.contains(previous.compute(0.5))
                let willBeInside = path.contains(next.compute(0.5))
                v.intersectionInfo.isEntry = !wasInside && willBeInside
                v.intersectionInfo.isExit = wasInside && !willBeInside
                if v.intersectionInfo.isEntry || v.intersectionInfo.isExit {
                    hasCrossing = true
                }
            }
            if !hasCrossing {
                nonCrossingComponents.append(self.path.subpaths[i])
            }
        }
    }
    
    private func forEachVertexStartingFrom(_ v: Vertex, _ callback: (Vertex) -> Void) {
        var current = v
        repeat {
            callback(current)
            current = current.next
        } while current !== v
    }
    
    private func forEachVertexInComponent(atIndex index: Int, _ callback: (Vertex) -> Void) {
        self.forEachVertexStartingFrom(lists[index].first!, callback)
    }
    
    func forEachVertex(_ callback: (Vertex) -> Void) {
        lists.forEach {
            self.forEachVertexStartingFrom($0.first!, callback)
        }
    }
}

internal enum BooleanPathOperation {
    case union
    case difference
    case intersection
}

internal class AugmentedGraph {
    
    func connectNeighbors(_ vertex1: Vertex, _ vertex2: Vertex) {
        vertex1.intersectionInfo.neighbor = vertex2
        vertex2.intersectionInfo.neighbor = vertex1
    }
    
    internal var list1: PathLinkedListRepresentation
    internal var list2: PathLinkedListRepresentation
    
    private let path1: Path
    private let path2: Path
    
    private var nonCrossingComponents1: [PathComponent] = []
    private var nonCrossingComponents2: [PathComponent] = []

    internal init(path1: Path, path2: Path, intersections: [PathIntersection]) {
        
        func intersectionVertexForPath(_ path: Path, at l: IndexedPathLocation) -> Vertex {
            let v = Vertex(location: path.point(at: l), isIntersection: true)
            return v
        }
        
        self.path1 = path1
        self.path2 = path2
        self.list1 = PathLinkedListRepresentation(path1)
        self.list2 = PathLinkedListRepresentation(path2)
        intersections.forEach {
            let vertex1 = intersectionVertexForPath(path1, at: $0.indexedPathLocation1)
            let vertex2 = intersectionVertexForPath(path2, at: $0.indexedPathLocation2)
            connectNeighbors(vertex1, vertex2) // sets the vertex crossing neighbor pointer
            list1.insertIntersectionVertex(vertex1, at: $0.indexedPathLocation1)
            list2.insertIntersectionVertex(vertex2, at: $0.indexedPathLocation2)
        }
        // mark each intersection as either entry or exit
        list1.markEntryExit(path2, &nonCrossingComponents1)
        list2.markEntryExit(path1, &nonCrossingComponents2)
    }
    
    private func shouldMoveForwards(fromVertex v: Vertex, forOperation operation: BooleanPathOperation, isOnFirstCurve: Bool) -> Bool {
        switch operation {
            case .union:
                return v.intersectionInfo.isExit
            case .difference:
                return isOnFirstCurve ? v.intersectionInfo.isExit : v.intersectionInfo.isEntry
            case .intersection:
                return v.intersectionInfo.isEntry
        }
    }
    
    internal func booleanOperation(_ operation: BooleanPathOperation) -> Path {
        // handle components that have no crossings
        func anyPointOnComponent(_ c: PathComponent) -> CGPoint {
            return c.curves[0].startingPoint
        }
        var pathComponents: [PathComponent] = []
        switch operation {
            case .union:
                pathComponents += nonCrossingComponents1.filter { path2.contains(anyPointOnComponent($0)) == false }
                pathComponents += nonCrossingComponents2.filter { path1.contains(anyPointOnComponent($0)) == false }
            case .difference:
                pathComponents += nonCrossingComponents1
                pathComponents += nonCrossingComponents2.filter { path1.contains(anyPointOnComponent($0)) == true }
            case .intersection:
                pathComponents += nonCrossingComponents1.filter { path2.contains(anyPointOnComponent($0)) == true }
                pathComponents += nonCrossingComponents2.filter { path1.contains(anyPointOnComponent($0)) == true }
        }
        // handle components that have crossings
        var unvisitedCrossings: Set<Vertex> = Set<Vertex>()
        list1.forEachVertex {
            if $0.isCrossing {
                unvisitedCrossings.insert($0)
            }
        }
        while unvisitedCrossings.count > 0 {
            
            var v = unvisitedCrossings.first!
            let start = v
            unvisitedCrossings.remove(v)
            
            var curves: [BezierCurve] = [BezierCurve]()
            var isOnFirstCurve = true
            var movingForwards = shouldMoveForwards(fromVertex: v, forOperation: operation, isOnFirstCurve: true)
            
            repeat {
                
                repeat {
                    if movingForwards {
                        curves.append(v.emitNext())
                        v = v.next
                    }
                    else {
                        curves.append(v.emitPrevious())
                        v = v.previous
                    }
                } while v.isCrossing == false
                
                if isOnFirstCurve {
                    unvisitedCrossings.remove(v)
                }
                
                v = v.intersectionInfo.neighbor!
                
                isOnFirstCurve = !isOnFirstCurve
                if isOnFirstCurve {
                    unvisitedCrossings.remove(v)
                }
                
                // decide on a (possibly) new direction
                movingForwards = shouldMoveForwards(fromVertex: v, forOperation: operation, isOnFirstCurve: isOnFirstCurve)

            } while v !== start
            
            // TODO: non-deterministic behavior from usage of Set when choosing starting vertex
            pathComponents.append(PathComponent(curves: curves))
        }
        return Path(subpaths: pathComponents)
    }
}

internal enum VertexTransition {
    case line
    case quadCurve(control: CGPoint)
    case curve(control1: CGPoint, control2: CGPoint)
    init(curve: BezierCurve) {
        switch curve {
        case is LineSegment:
            self = .line
        case let quadCurve as QuadraticBezierCurve:
            self = .quadCurve(control: quadCurve.p1)
        case let cubicCurve as CubicBezierCurve:
            self = .curve(control1: cubicCurve.p1, control2: cubicCurve.p2)
        default:
            fatalError("Vertex does not support curve type (\(type(of: curve))")
        }
    }
}

internal class Vertex {
    public let location: CGPoint
    public let isIntersection: Bool
    // pointers must be set after initialization
    
    public struct IntersectionInfo {
        public var isEntry: Bool = false
        public var isExit: Bool = false
        public var neighbor: Vertex? = nil
    }
    public var intersectionInfo: IntersectionInfo = IntersectionInfo()
    
    public var isCrossing: Bool {
        return self.isIntersection && (self.intersectionInfo.isEntry || self.intersectionInfo.isExit)
    }
    
    internal struct SplitInfo {
        var t: CGFloat
    }
    internal var splitInfo: SplitInfo? = nil // non-nil only when vertex is inserted by splitting an element
    
    public private(set) var next: Vertex! = nil
    public private(set) weak var previous: Vertex! = nil
    public private(set) var nextTransition: VertexTransition! = nil
    
    public func setNextVertex(_ vertex: Vertex, transition: VertexTransition) {
        self.next = vertex
        self.nextTransition = transition
    }
    
    public func setPreviousVertex(_ vertex: Vertex) {
        self.previous = vertex
    }
    
    init(location: CGPoint, isIntersection: Bool) {
        self.location = location
        self.isIntersection = isIntersection
    }
    
    internal func emitTo(_ end: CGPoint, using transition: VertexTransition) -> BezierCurve {
        switch transition {
        case .line:
            return LineSegment(p0: self.location, p1: end)
        case .quadCurve(let c):
            return QuadraticBezierCurve(p0: self.location, p1: c, p2: end)
        case .curve(let c1, let c2):
            return CubicBezierCurve(p0: self.location, p1: c1, p2: c2, p3: end)
        }
    }
    
    public func emitNext() -> BezierCurve {
        return self.emitTo(next.location, using: nextTransition)
    }
    
    public func emitPrevious() -> BezierCurve {
        return self.previous.emitNext().reversed()
    }
}

extension Vertex: Equatable {
    public static func == (left: Vertex, right: Vertex) -> Bool {
        return left === right
    }
}

extension Vertex: Hashable {
    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
}

