function Modal({ isModalOpen, closeModal, children }) {
  if (!isModalOpen) {
    return null;
  }

  return (
    <div className="modal-shell" role="dialog" aria-modal="true">
      <button className="modal-overlay" type="button" aria-label="Close modal" onClick={closeModal} />
      <div className="modal-panel">
        {children}
      </div>
    </div>
  );
}

export default Modal;
