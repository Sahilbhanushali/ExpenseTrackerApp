/// Money that moves without being income or spending: transfers between
/// your accounts, and (in later phases) card bill payments, loan principal,
/// savings contributions and reconciliation adjustments.
///
/// A movement is one event; its [Posting]s are the sides it touches, all
/// sharing the movement's id and [ref]. Postings of one movement sum to
/// zero when money stays inside your own books (a transfer: −A, +B).
enum MovementKind {
  transfer,
  adjustment,

  /// Bank → card: settles card debt; never an expense (rule 2).
  cardPayment,

  /// Bank → loan: principal only (rule 3). Interest is an expense txn.
  loanPrincipal,

  /// Loan → bank: a disbursed loan's money arriving. Not income.
  loanOpen,
}

/// Planned movements are intentions (an approved allocation not yet done
/// at the bank); only completed ones change balances.
enum MovementStatus { planned, completed, cancelled }

/// What a posting is attached to. Cards, loans and goals arrive in later
/// phases; `external` is money leaving or entering your books entirely.
///
/// On a card or loan, a positive posting reduces what you owe.
enum PostingOwner { account, external, card, loan }

class Posting {
  final int? id;
  final int movementId;
  final PostingOwner ownerType;
  final int? ownerId;

  /// Signed paise: negative leaves the owner, positive arrives.
  final int amountPaise;

  const Posting({
    this.id,
    required this.movementId,
    required this.ownerType,
    this.ownerId,
    required this.amountPaise,
  });

  Map<String, Object?> toMap() => {
    'movement_id': movementId,
    'owner_type': ownerType.name,
    'owner_id': ownerId,
    'amount': amountPaise,
  };
}

MovementStatus movementStatusFrom(String? v) => MovementStatus.values
    .firstWhere((s) => s.name == v, orElse: () => MovementStatus.completed);
