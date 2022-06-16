# Dx iOS Modularization Part I

In this topic we will fix the existing Dependency Injection (DI) mechanism established on Dx iOS.

## Overview
Before we start let's understand why existing solution doesn't fit our needs and must be re-worked.
Today we provide this API to handle DI:

    class SomeClass {
        @Resolved private var serviceA: ServiceA! // (1)

        private var name: String
        
        init(name: String) { // (2)
            self.name = name
        }
        
        func doSomething() {
            serviceA.foo() // (3)
        }
    }

1. Declare dependency on serviceA through property wrapper **@Resolved**.
2. Declare constructor **hiding** dependencies!
3. Invoke some method on serviceA dependency

## @Resolved inside

Let's take a look underneath the hood of the property wrapper implementation:

    @propertyWrapper
    public struct Resolved<Service> {
        /// The wrapped value - getter only. Returns the instance from the service resolver for the specific service type
        public var wrappedValue: Service? {
            if Service.self == ServiceResolution.self {
                return ServiceResolver.shared as? Service // (1)
            } else {
                return ServiceResolver.shared.resolve(service: serviceType) // (2)
            }
        }
    ...

1 and 2 are links to the **ServiceResolver** class's shared state.

    public final class ServiceResolver: ServiceResolution {
        
        /// The dictionary storing the factory closures and their associated service type identifiers
        private var factoryStorage = [ServiceType: () -> Any]()
        
        /// The service cache for instantiated services
        private var serviceCache = [ServiceType: Any]()
    
        /// The shared instance generated for main point of service access
        internal static var shared: ServiceResolution = ServiceResolver() // <- This!
    ...


## What's wrong?

This is very *convenient* way of coding, e.g. type **@Resolved** anywhere and you're all set! On the other hand there are several issues here:

1. There is no vision for the user of the API of **SomeClass** that there is actually some dependency on *serviceA*.
2. There is no way to manage the dependency, let's say I want to replace the **ServiceA** implementation with something different, or mock it for unit-tests.
3. Let's go deeper into **@Resolved** guts and see that this is actually nothing but Singleton, which leads us to another problem of shared state. Means that the existing API doesn't allow us to have independent instances of **SomeClass** which are not sharing the same state. Singleton itself violates single-responsibility principle of SOLID in Object-Oriented paradigm.
4. Since **@Resolved** is nothing but *Singleton*, aka shared state, and the hidden declaration (see point 1), Unit-testing of this class becomes challenging and breaks independent/isolated rule of F.I.R.S.T. principle of Unit-test. 

## What is Dependency Injection?

First of all let's understand what is DI and what's not!

> Dependency injection is a design pattern in which an object receives
> other objects that it depends on. A form of inversion of control,
> dependency injection aims to separate the concerns of constructing
> objects and using them, leading to loosely coupled programs The
> pattern ensures that an object which wants to use a given service
> should not have to know how to construct those services. Instead, the
> receiving object (or 'client') is provided with its dependencies by
> external code (an 'injector'), which it is not aware of.

According to wiki: https://en.wikipedia.org/wiki/Dependency_injection

This means that the property wrapper with and the ServiceResolver are not actually related to DI pattern, but are *injectors*! However, following the quote above client should not be aware of *injectors*. Since we keep **@Resolved** inside client's code, we violating the one more pattern. Moreover, if we go deeper to the property wrapper implementation we will realize that all dependencies are *Optionals*! Not only our *clients* aware of injectors but they're dealing with optional dependecies, which will lead to crashes in production...

## Solution

In order to solve DI, let's make APIs honest by obscuring underlying dependencies to the clients (and in future avoid making hidden dependencies).

    class SomeClass {
        private let serviceA: ServiceA // (1)
    
        private var name: String
        
        init(name: String, serviceA: ServiceA) { // (2)
            self.name = name
            self.serviceA = serviceA
        }
        ...
    }

1. Get rid of extra knowledge of injector, make it safer by having **ServiceA** type non-optional. Won't crash like in the original version.
2. Put service into constructor, so that clients will know exactly which dependencies this object requires.

Depends on the need *serviceA* can be **public**, **variable** but NOT related to **ServiceResolver** or **@Resolved** property wrapper.

## What about convenience and legacy code?

Today there are **~1600** usages of the **@Resolved** property wrapper in the project. It's reasonable to ask, how to fix the issue and not break the project? And how about convenience, where should we take all those dependencies if not from **ServiceResolver** itself? Let's use convenience constructor in extension:

    extension SomeClass {
        convenience init(name: String) {
            @Resolved var serviceA: ServiceA!
            self.init(name: name, serviceA: serviceA)
        }
    }

We keep the signature of our object's constructor the same, the legacy code won't break! 
**Important:** this extension must be separate from the **SomeClass** implementation and **Domain**, it's crucial to keep **Injector** knowledge out! This is required to Dx iOS Modularization Part II.

## Unit-tests

As a result of this change some tests may and should fail. The reason is they are already wrong. Why so? Because of the shared state. Today lots of tests are *valid* if only we run them in specific order, one by one! They are not isolated and independant, that's why some tests rely on *leftovers* from preceding tests. Leftovers are mock services configured through the *Singleton* for needs of other tests. So, even if some tests will fail this is a good sign, we just have to fix them to use their own configurations, rather than random one from unknown precondition.

Finally, if we'll extrapolate this practice to the entire Dx iOS project, we can call our tests unit-tests, we can rely on their result, we can run them in parallel and reduce pipelines build time.
