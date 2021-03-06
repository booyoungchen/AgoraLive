//
//  LiveListTabViewController.swift
//  AgoraLive
//
//  Created by CavanSu on 2020/2/19.
//  Copyright © 2020 Agora. All rights reserved.
//

import UIKit
import RxSwift
import RxRelay
import MJRefresh
import MBProgressHUD
import AgoraRtcKit

class LiveListTabViewController: MaskViewController {
    @IBOutlet weak var tabView: TabSelectView!
    @IBOutlet weak var createButton: UIButton!
    
    private let listVM = LiveListVM()
    private let bag = DisposeBag()
    private let monitor = NetworkMonitor(host: "www.apple.com")
    private var listVC: LiveListViewController?
    private var timer: Timer?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        roomListRefresh(false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelScheduelRefresh()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateViews()
        
        // TabSelectView
        updateTabSelectView()
        // LiveListViewController
        updateLiveListVC()
        
        netMonitor()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let segueId = segue.identifier else {
            return
        }
        
        switch segueId {
        case "LiveListViewController":
            listVC = segue.destination as? LiveListViewController
        case "CreateLiveNavigation":
            guard let sender = sender,
                let type = sender as? LiveType,
                let navi = segue.destination as? UINavigationController,
                let vc = navi.viewControllers.first as? CreateLiveViewController else {
                    assert(false)
                    return
            }
            
            vc.liveType = type
        case "MultiBroadcastersViewController":
            guard let sender = sender,
                let info = sender as? LiveSession.JoinedInfo,
                let seatInfo = info.seatInfo else {
                    assert(false)
                    return
            }
            
            let vc = segue.destination as? MultiBroadcastersViewController
            vc?.hidesBottomBarWhenPushed = true
            vc?.audienceListVM.updateGiftListWithJson(list: info.giftAudience)
            vc?.seatVM = try! LiveSeatVM(list: seatInfo)
        case "SingleBroadcasterViewController":
            guard let sender = sender,
                let info = sender as? LiveSession.JoinedInfo else {
                    fatalError()
            }
            
            let vc = segue.destination as? SingleBroadcasterViewController
            vc?.hidesBottomBarWhenPushed = true
            vc?.audienceListVM.updateGiftListWithJson(list: info.giftAudience)
        case "PKBroadcastersViewController":
            guard let sender = sender,
                let info = sender as? LiveSession.JoinedInfo else {
                    fatalError()
            }
            
            var statistics: PKStatistics
            
            if let pkInfo = info.pkInfo {
                statistics = try! PKStatistics(dic: pkInfo)
            } else {
                statistics = PKStatistics(state: .none)
            }
            
            let vc = segue.destination as? PKBroadcastersViewController
            vc?.hidesBottomBarWhenPushed = true
            vc?.audienceListVM.updateGiftListWithJson(list: info.giftAudience)
            vc?.pkVM = PKVM(statistics: statistics)
        case "VirtualBroadcastersViewController":
            guard let sender = sender,
                let info = sender as? LiveSession.JoinedInfo,
                let seatInfo = info.seatInfo,
                let session = ALCenter.shared().liveSession else {
                    fatalError()
            }
            
            let vc = segue.destination as? VirtualBroadcastersViewController
            vc?.hidesBottomBarWhenPushed = true
            vc?.audienceListVM.updateGiftListWithJson(list: info.giftAudience)
            let seatVM = try! LiveSeatVM(list: seatInfo)
            vc?.seatVM = seatVM
            
            var broadcasting: VirtualVM.Broadcasting
            
            if seatVM.list.value.count == 1,
                let remote = seatVM.list.value[0].user {
                broadcasting = .multi([session.owner.user, remote])
            } else {
                broadcasting = .single(session.owner.user)
            }
            
            if let virtualAppearance = info.virtualAppearance {
                vc?.enhancementVM.virtualAppearance(VirtualAppearance.item(virtualAppearance))
            }
            
            vc?.virtualVM = VirtualVM(broadcasting: BehaviorRelay(value: broadcasting))
        default:
            break
        }
    }
}

private extension LiveListTabViewController {
    func updateViews() {
        createButton.layer.shadowOpacity = 0.3
        createButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        createButton.layer.shadowColor = UIColor(hexString: "#BD3070").cgColor
        
        createButton.rx.tap.subscribe(onNext: { [unowned self] in
            if self.listVM.presentingType != .virtualBroadcasters {
                self.performSegue(withIdentifier: "CreateLiveNavigation", sender: self.listVM.presentingType)
            } else {
                self.performSegue(withIdentifier: "VirtualCreatNavigation", sender: nil)
            }
        }).disposed(by: bag)
    }
    
    func updateTabSelectView() {
        tabView.underlineHeight = 3
        tabView.titleSpace = 28
        
        let titles = LiveType.list.map { (item) -> String in
            return item.description
        }
        
        tabView.update(titles)
        
        tabView.selectedIndex.subscribe(onNext: { [unowned self] (index) in
            var type: LiveType
            
            switch index {
            case 0: type = .multiBroadcasters
            case 1: type = .singleBroadcaster
            case 2: type = .pkBroadcasters
            case 3: type = .virtualBroadcasters
            default: fatalError()
            }
            
            self.listVM.presentingType = type
            
            self.roomListRefresh(false)
        }).disposed(by: bag)
    }
    
    func updateLiveListVC() {
        guard let vc = listVC else {
            assert(false)
            return
        }
        
        // placeHolderView tap
        vc.placeHolderView.tap.subscribe(onNext: { [unowned self] (_) in
            self.roomListRefresh(true)
        }).disposed(by: bag)
        
        // placeHolderView if need hidden
        listVM.presentingList.subscribe(onNext: { [unowned vc] (list) in
            vc.collectionView.isHidden = list.count == 0 ? true : false
        }).disposed(by: bag)
        
        // Cell Reload
        listVM.presentingList
            .bind(to: vc.collectionView.rx.items(cellIdentifier: "RoomCell",
                                                 cellType: RoomCell.self)) { index, item, cell in
                                                    cell.briefView.label.text = item.name
                                                    cell.personCountView.label.text = "\(item.personCount)"
                                                    cell.briefView.imageView.image = ALCenter.shared().centerProvideImagesHelper().getRoom(index: item.imageIndex)
        }.disposed(by: bag)
        
        // MJRefresh
        vc.collectionView.mj_header = MJRefreshNormalHeader(refreshingBlock: { [unowned self, unowned vc] in
            self.listVM.refetch(success: {
                vc.collectionView.mj_header?.endRefreshing()
            }) { [unowned vc] in // fail
                vc.collectionView.mj_header?.endRefreshing()
            }
        })
        
        vc.collectionView.mj_footer = MJRefreshBackFooter(refreshingBlock: { [unowned self, unowned vc] in
            self.listVM.fetch(success: {
                vc.collectionView.mj_footer?.endRefreshing()
            }) { [unowned vc] in // fail
                vc.collectionView.mj_footer?.endRefreshing()
            }
        })
        
        vc.collectionView.rx.modelSelected(RoomBrief.self).subscribe(onNext: { [unowned self] (room) in
            let type = self.listVM.presentingType
            var settings = LocalLiveSettings(title: room.name)
            var media = settings.media
            
            switch type {
            case .multiBroadcasters:
                media.resolution = AgoraVideoDimension240x240
                media.frameRate = .fps15
                media.bitRate = 200
            case .singleBroadcaster:
                media.resolution = CGSize.AgoraVideoDimension360x640
                media.frameRate = .fps15
                media.bitRate = 600
            case .pkBroadcasters:
                media.resolution = CGSize.AgoraVideoDimension360x640
                media.frameRate = .fps15
                media.bitRate = 800
            case .virtualBroadcasters:
                media.resolution = CGSize.AgoraVideoDimension720x1280
                media.frameRate = .fps15
                media.bitRate = 1000
            }
            
            settings.media = media
            
            let session = LiveSession(roomId: room.roomId,
                                      settings: settings,
                                      type: type)
            self.joinLiving(session: session)
        }).disposed(by: bag)
        
        vc.collectionView.rx.willBeginDragging.subscribe(onNext: { [unowned self] in
            self.cancelScheduelRefresh()
        }).disposed(by: bag)
        
        vc.collectionView.rx.didEndDragging.subscribe(onNext: { [unowned self] (done) in
            if done {
                self.perMinuterRefresh()
            }
        }).disposed(by: bag)
    }
        
    func netMonitor() {
        monitor.action(.on)
        monitor.connect.subscribe(onNext: { [unowned self] (status) in
            switch status {
            case .notReachable: self.listVC?.placeHolderView.viewType = .lostConnection
            case .reachable:    self.listVC?.placeHolderView.viewType = .noRoom
            default: break
            }
        }).disposed(by: bag)
    }
    
    func perMinuterRefresh() {
        timer = Timer(fireAt: Date(timeIntervalSinceNow: 60.0),
                      interval: 60.0,
                      target: self,
                      selector: #selector(roomListRefresh),
                      userInfo: nil,
                      repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        timer?.fire()
    }
    
    @objc func roomListRefresh(_ hasHUD: Bool = false) {
        guard !self.isShowingHUD() else {
            return
        }
        
        if let isRefreshing = self.listVC?.collectionView.mj_header?.isRefreshing,
            isRefreshing {
            return
        }
        
        let end: Completion = { [unowned self] in
            if hasHUD {
                self.hiddenHUD()
            }
        }

        if hasHUD {
            self.showHUD()
        }
        
        listVM.refetch(success: end, fail: end)
    }
    
    func cancelScheduelRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

extension LiveListTabViewController {
    func joinLiving(session: LiveSession) {
        self.showHUD()
        
        let center = ALCenter.shared()
        center.liveSession = session
        session.join(success: { [unowned session, unowned self] (info: LiveSession.JoinedInfo) in
            self.hiddenHUD()
            
            switch session.type {
            case .multiBroadcasters:
                self.performSegue(withIdentifier: "MultiBroadcastersViewController", sender: info)
            case .singleBroadcaster:
                self.performSegue(withIdentifier: "SingleBroadcasterViewController", sender: info)
            case .pkBroadcasters:
                self.performSegue(withIdentifier: "PKBroadcastersViewController", sender: info)
            case .virtualBroadcasters:
                self.performSegue(withIdentifier: "VirtualBroadcastersViewController", sender: info)
            }
        }) { [unowned self] in
            self.hiddenHUD()
            self.showAlert(message:"join live fail")
        }
    }
}
