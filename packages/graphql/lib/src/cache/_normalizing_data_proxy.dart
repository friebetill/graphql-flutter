import "package:meta/meta.dart";

import 'package:gql_exec/gql_exec.dart' show Request;
import 'package:gql/ast.dart' show DocumentNode;

import 'package:normalize/normalize.dart';

import './data_proxy.dart';
import '../utilities/helpers.dart';

typedef DataIdResolver = String Function(Map<String, Object> object);

/// Implements the core (de)normalization api leveraged by the cache and proxy,
///
/// [readNormalized] and [writeNormalized] must still be supplied by the implementing class
abstract class NormalizingDataProxy extends GraphQLDataProxy {
  /// `typePolicies` to pass down to `normalize`
  Map<String, TypePolicy> typePolicies;

  /// Whether to add `__typename` automatically.
  ///
  /// This is `false` by default because [gql] automatically adds `__typename` already.
  ///
  /// If [addTypename] is true, it is important for the client
  /// to add `__typename` to each request automatically as well.
  /// Otherwise, a round trip to the cache will nullify results unless
  /// [returnPartialData] is `true`
  bool addTypename = false;

  /// Used for testing
  @protected
  bool get returnPartialData => false;

  /// Flag used to request a (re)broadcast from the [QueryManager]
  @protected
  bool broadcastRequested = false;

  /// Optional `dataIdFromObject` function to pass through to [normalize]
  DataIdResolver dataIdFromObject;

  /// Read normaized data from the cache
  ///
  /// Called from [readQuery] and [readFragment], which handle denormalization.
  ///
  /// The key differentiating factor for an implementing `cache` or `proxy`
  /// is usually how they handle [optimistic] reads.
  @protected
  dynamic readNormalized(String rootId, {bool optimistic});

  /// Write normalized data into the cache.
  ///
  /// Called from [writeQuery] and [writeFragment].
  /// Implementors are expected to handle deep merging results themselves
  @protected
  void writeNormalized(String dataId, dynamic value);

  /// Variable sanitizer for referencing custom scalar types in cache keys.
  @protected
  SanitizeVariables sanitizeVariables;

  Map<String, dynamic> readQuery(
    Request request, {
    bool optimistic = true,
  }) =>
      denormalizeOperation(
        read: (dataId) => readNormalized(dataId, optimistic: optimistic),
        document: request.operation.document,
        operationName: request.operation.operationName,
        variables: sanitizeVariables(request.variables),
        typePolicies: typePolicies,
        addTypename: addTypename ?? false,
        returnPartialData: returnPartialData,
      );

  Map<String, dynamic> readFragment({
    @required DocumentNode fragment,
    @required Map<String, dynamic> idFields,
    String fragmentName,
    Map<String, dynamic> variables,
    bool optimistic = true,
  }) =>
      denormalizeFragment(
        read: (dataId) => readNormalized(dataId, optimistic: optimistic),
        document: fragment,
        idFields: idFields,
        fragmentName: fragmentName,
        variables: sanitizeVariables(variables),
        typePolicies: typePolicies,
        addTypename: addTypename ?? false,
        dataIdFromObject: dataIdFromObject,
        returnPartialData: returnPartialData,
      );

  void writeQuery(
    Request request, {
    Map<String, dynamic> data,
    bool broadcast = true,
  }) {
    normalizeOperation(
      write: (dataId, value) => writeNormalized(dataId, value),
      document: request.operation.document,
      operationName: request.operation.operationName,
      variables: sanitizeVariables(request.variables),
      data: data,
      typePolicies: typePolicies,
      dataIdFromObject: dataIdFromObject,
    );
    if (broadcast ?? true) {
      broadcastRequested = true;
    }
  }

  void writeFragment({
    @required DocumentNode fragment,
    @required Map<String, dynamic> idFields,
    @required Map<String, dynamic> data,
    String fragmentName,
    Map<String, dynamic> variables,
    bool broadcast = true,
  }) {
    normalizeFragment(
      write: (dataId, value) => writeNormalized(dataId, value),
      read: (dataId) => null,
      document: fragment,
      idFields: idFields,
      data: data,
      fragmentName: fragmentName,
      variables: sanitizeVariables(variables),
      typePolicies: typePolicies,
      dataIdFromObject: dataIdFromObject,
    );
    if (broadcast ?? true) {
      broadcastRequested = true;
    }
  }
}
