// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

// Just enough linear algebra for the pointer solver. Deliberately not simd: these types cross
// into @objc code and unit tests, they are used a few hundred times a second at most, and
// keeping them plain makes the sign conventions below inspectable.
//
// Deliberately free of CoreMotion, which is an iOS-only framework. Keeping the geometry
// platform-independent is what lets the pointer maths be compiled and exercised as plain Swift
// -- the sign conventions here are the easiest thing in this feature to get wrong and the
// hardest to debug on a device, so being able to assert on them off-device is worth the one
// conversion at the CoreMotion boundary (see VirtualWiiRemote.ingest).

public struct Vector3: Equatable {
  public var x: Double
  public var y: Double
  public var z: Double

  public static let zero = Vector3(x: 0, y: 0, z: 0)

  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  public var length: Double {
    return (x * x + y * y + z * z).squareRoot()
  }

  public var normalized: Vector3 {
    let l = length
    // A zero-length vector has no direction to preserve, and dividing would produce NaNs that
    // then poison every axis written to StateManager for the rest of the session.
    guard l > 1e-12 else {
      return Vector3.zero
    }

    return Vector3(x: x / l, y: y / l, z: z / l)
  }

  public static func + (a: Vector3, b: Vector3) -> Vector3 {
    return Vector3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
  }

  public static func - (a: Vector3, b: Vector3) -> Vector3 {
    return Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
  }

  public static func * (v: Vector3, s: Double) -> Vector3 {
    return Vector3(x: v.x * s, y: v.y * s, z: v.z * s)
  }

  public static func dot(_ a: Vector3, _ b: Vector3) -> Double {
    return a.x * b.x + a.y * b.y + a.z * b.z
  }

  public static func cross(_ a: Vector3, _ b: Vector3) -> Vector3 {
    return Vector3(
      x: a.y * b.z - a.z * b.y,
      y: a.z * b.x - a.x * b.z,
      z: a.x * b.y - a.y * b.x
    )
  }
}

// A right-handed orthonormal pointing frame: where the emitter aims, and how "up" and "right"
// are oriented around that aim.
//
// The handedness convention is fixed by `right = forward x up`, which is the same one OpenGL
// uses for (right, up, -forward). Sanity check, in a world where +Y is the direction you're
// facing and +Z is up: forward = +Y, up = +Z gives right = Y x Z = +X, i.e. your right hand
// side. Getting this backwards mirrors the pointer horizontally, so it is worth the check.
public struct PointingFrame {
  public let forward: Vector3
  public let up: Vector3
  public let right: Vector3

  // Orthonormalises whatever it's handed: `up` only has to be roughly up, it does not have to
  // be perpendicular to `forward`.
  public init(forward: Vector3, up: Vector3) {
    let f = forward.normalized
    var r = Vector3.cross(f, up).normalized

    // Degenerate only when `up` is parallel to `forward`. Pick any perpendicular rather than
    // returning a frame full of zeros, which would silently peg the pointer to a corner.
    if r == Vector3.zero {
      let fallback = abs(f.z) < 0.9 ? Vector3(x: 0, y: 0, z: 1) : Vector3(x: 1, y: 0, z: 0)
      r = Vector3.cross(f, fallback).normalized
    }

    self.forward = f
    self.right = r
    self.up = Vector3.cross(r, f)
  }
}

/// A 3x3 rotation, row-major. Mirrors CoreMotion's CMRotationMatrix field for field so the
/// conversion at the boundary is mechanical, without dragging CoreMotion into the geometry.
public struct RotationMatrix3 {
  public var m11, m12, m13: Double
  public var m21, m22, m23: Double
  public var m31, m32, m33: Double

  public static let identity = RotationMatrix3(
    m11: 1, m12: 0, m13: 0,
    m21: 0, m22: 1, m23: 0,
    m31: 0, m32: 0, m33: 1
  )

  public init(m11: Double, m12: Double, m13: Double,
              m21: Double, m22: Double, m23: Double,
              m31: Double, m32: Double, m33: Double) {
    self.m11 = m11
    self.m12 = m12
    self.m13 = m13
    self.m21 = m21
    self.m22 = m22
    self.m23 = m23
    self.m31 = m31
    self.m32 = m32
    self.m33 = m33
  }

  /// Right-handed rotation of `radians` about `axis`, by the usual right-hand rule: with the
  /// thumb along the axis, positive angles turn the way the fingers curl.
  public static func rotation(radians: Double, about axis: Vector3) -> RotationMatrix3 {
    let a = axis.normalized
    let c = cos(radians)
    let s = sin(radians)
    let t = 1 - c

    return RotationMatrix3(
      m11: t * a.x * a.x + c, m12: t * a.x * a.y - s * a.z, m13: t * a.x * a.z + s * a.y,
      m21: t * a.x * a.y + s * a.z, m22: t * a.y * a.y + c, m23: t * a.y * a.z - s * a.x,
      m31: t * a.x * a.z - s * a.y, m32: t * a.y * a.z + s * a.x, m33: t * a.z * a.z + c
    )
  }
}

// Maps a vector from the CoreMotion *device* frame into the attitude's *reference* frame.
//
// ASSUMPTION, and the one place to fix it: CMAttitude.rotationMatrix is treated as
// device -> reference. This is the convention in which a device lying flat on its back has the
// identity matrix and CMDeviceMotion.gravity reads (0, 0, -1) in both frames, and it is the
// convention behind the usual "aim direction = rotationMatrix * (0,0,-1)" recipe.
//
// This has NOT been confirmed on hardware. If the convention is actually reference -> device,
// the symptom is a pointer that responds to aiming but along mirrored or swapped axes, and the
// fix is to transpose here (read the matrix column-wise instead of row-wise) -- nothing else in
// the solver needs to change, because every vector it compares passes through this function.
public func worldFromDevice(_ v: Vector3, _ m: RotationMatrix3) -> Vector3 {
  return Vector3(
    x: m.m11 * v.x + m.m12 * v.y + m.m13 * v.z,
    y: m.m21 * v.x + m.m22 * v.y + m.m23 * v.z,
    z: m.m31 * v.x + m.m32 * v.y + m.m33 * v.z
  )
}
