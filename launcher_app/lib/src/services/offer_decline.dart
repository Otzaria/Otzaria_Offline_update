class OfferDecline {
  int _declined = 0;

  int filter(int count) {
    return count > _declined ? count : 0;
  }

  void mark(int count) => _declined = count;
}
