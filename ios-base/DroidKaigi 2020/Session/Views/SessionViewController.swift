import ios_combined
import MaterialComponents
import RxCocoa
import RxSwift
import UIKit

final class SessionViewController: UIViewController {
    private let disposeBag = DisposeBag()

    @IBOutlet weak var filteredSessionCountLabel: UILabel! {
        didSet {
            filteredSessionCountLabel.font = ApplicationScheme.shared.typographyScheme.caption
        }
    }

    @IBOutlet weak var filterButton: MDCButton! {
        didSet {
            filterButton.isSelected = true
            filterButton.applyTextTheme(withScheme: ApplicationScheme.shared.buttonScheme)
            let filterListImage = Asset.icFilterList.image
            let templateFilterListImage = filterListImage.withRenderingMode(.alwaysTemplate)
            filterButton.setImage(templateFilterListImage, for: .selected)
            let arrowUpImage = Asset.icKeyboardArrowUp.image
            let templateArrowUpImage = arrowUpImage.withRenderingMode(.alwaysTemplate)
            filterButton.setImage(templateArrowUpImage, for: .normal)
            filterButton.setTitle("Filter", for: .selected)
            filterButton.setTitle("", for: .normal)
        }
    }

    @IBOutlet weak var collectionView: UICollectionView! {
        didSet {
            collectionView.register(UINib(nibName: "SessionCell", bundle: nil), forCellWithReuseIdentifier: SessionCell.identifier)
            let layout = UICollectionViewFlowLayout()
            layout.estimatedItemSize = .init(width: UIScreen.main.bounds.width, height: SessionCell.rowHeight)
            collectionView.collectionViewLayout = layout
        }
    }

    private let filterViewModel: FilterViewModel
    private let sessionViewModel: SessionViewModel
    private let type: SessionViewControllerType

    init(filterViewModel: FilterViewModel, sessionViewModel: SessionViewModel, sessionViewType: SessionViewControllerType) {
        self.filterViewModel = filterViewModel
        self.sessionViewModel = sessionViewModel
        type = sessionViewType
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        filteredSessionCountLabel.isHidden = type == .event
        filterButton.isHidden = type == .event

        filterButton.rx.tap.asSignal()
            .emit(to: Binder(self) { me, _ in
                me.filterViewModel.toggleEmbeddedView()
            })
            .disposed(by: disposeBag)
        filterViewModel.isFocusedOnEmbeddedView
            .drive(filterButton.rx.isSelected)
            .disposed(by: disposeBag)

        filterViewModel.selectedSessionContents
            .drive(Binder(self) { me, sessionContents in
                me.sessionViewModel.selectedFilterSessionContents(sessionContents)
            })
            .disposed(by: disposeBag)

        // TODO: Error handling for viewModel.sessions
        let dataSource = SessionViewDataSource(type: type)
        let filteredSessions = sessionViewModel.sessions.asObservable()
            .map { [weak self] sessions -> [Session] in
                guard let self = self else { return [] }
                switch self.type {
                case .day1, .day2:
                    return sessions.filter {
                        Int($0.dayNumber) == self.type.rawValue
                            && $0.room.roomType != .exhibition
                    }
                case .event:
                    return sessions.filter { $0.room.roomType == .exhibition }
                case .myPlan:
                    return sessions.filter { $0.isFavorited }
                }
            }
            .share(replay: 1, scope: .whileConnected)

        filteredSessions
            .bind(to: collectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)

        filteredSessions
            .filter { [weak self] _ in self?.type == .myPlan }
            .map { $0.isEmpty }
            .bind(to: Binder(self) { me, isEmpty in
                if isEmpty {
                    me.showSuggestView()
                } else {
                    me.removeSuggestView()
                }
            })
            .disposed(by: disposeBag)

        filterViewModel.selectedSessionContents.asObservable()
            .withLatestFrom(filteredSessions) { ($0, $1) }
            .bind(to: Binder(self) { me, args in
                let (sessionContents, sessions) = args
                if sessionContents.isEmpty {
                    me.filteredSessionCountLabel.isHidden = true
                } else {
                    me.filteredSessionCountLabel.isHidden = false
                    me.filteredSessionCountLabel.text = "\(L10n.applicableSession): \(sessions.count)"
                }
            }).disposed(by: disposeBag)

        dataSource.onTapSpeaker
            .emit(onNext: { [weak self] speaker, sessions in
                self?.navigationController?.pushViewController(SpeakerViewController.instantiate(speaker: speaker, sessions: sessions), animated: true)
            })
            .disposed(by: disposeBag)
        dataSource.onTapBookmark.emit(onNext: { [unowned self] session in
            if session.isFavorited {
                self.sessionViewModel.resignBookingSession(session)
            } else {
                self.sessionViewModel.bookSession(session)
            }
            })
            .disposed(by: disposeBag)
        collectionView.rx.modelSelected(Session.self)
            .bind(onNext: { [unowned self] in self.showDetail(forSession: $0) })
            .disposed(by: disposeBag)
    }

    func showSuggestView() {
        let suggestView = SuggestView()
        view.addSubview(suggestView)
        suggestView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            suggestView.topAnchor.constraint(equalTo: view.topAnchor),
            suggestView.leftAnchor.constraint(equalTo: view.leftAnchor),
            suggestView.rightAnchor.constraint(equalTo: view.rightAnchor),
            suggestView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func removeSuggestView() {
        if let suggestView = view.subviews.first(where: { $0 is SuggestView }) {
            suggestView.removeFromSuperview()
        }
    }
}
