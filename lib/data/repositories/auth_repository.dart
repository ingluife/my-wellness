import '../models/app_state.dart';

/// Who is using the app, and where their data lives.
///
/// The mobile flavour of openGym has no account at all: the phone *is* the profile. This app
/// keeps that as the default, but puts the seam here rather than assuming it — so Firebase
/// Auth and Firestore sync can be dropped in behind these two interfaces without any screen,
/// store or model changing shape.

/// A signed-in person.
class AuthUser {
  const AuthUser({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class AuthRepository {
  /// The current user, or null in guest mode.
  AuthUser? get currentUser;

  /// Whether signing in is offered at all. False in a local-only build, which is what makes
  /// the Login screen show only the guest path rather than dead buttons.
  bool get isAvailable;

  Stream<AuthUser?> get changes;

  Future<AuthUser?> signIn();

  Future<AuthUser?> createProfile(String name);

  Future<void> signOut();
}

/// Pulling the training log to and from somewhere else.
abstract interface class RemoteSync {
  bool get isAvailable;

  /// Push the local state up. Never throws: a failed push marks the state dirty and is retried,
  /// because losing a set because the network was down is not acceptable.
  Future<void> push(AppState state);

  /// Fetch the remote state, or null when there is none.
  Future<AppState?> pull();
}

/// The local-only implementation this build ships with.
///
/// It is not a stub in the sense of being unfinished — it is the correct behaviour for an app
/// whose whole premise is that the data never leaves the phone. Replacing it is a choice, not
/// a completion.
class LocalOnlyAuth implements AuthRepository {
  const LocalOnlyAuth();

  @override
  AuthUser? get currentUser => null;

  @override
  bool get isAvailable => false;

  @override
  Stream<AuthUser?> get changes => const Stream.empty();

  @override
  Future<AuthUser?> signIn() async => null;

  @override
  Future<AuthUser?> createProfile(String name) async => null;

  @override
  Future<void> signOut() async {}
}

class NoRemoteSync implements RemoteSync {
  const NoRemoteSync();

  @override
  bool get isAvailable => false;

  @override
  Future<void> push(AppState state) async {}

  @override
  Future<AppState?> pull() async => null;
}
