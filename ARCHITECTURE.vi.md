# Kiến trúc — Logger này hoạt động như thế nào

> [English](ARCHITECTURE.md) | Tiếng Việt

Tài liệu này giải thích mọi thành phần của package Logger, hành trình của một log event qua hệ thống, và thành phần nào chịu trách nhiệm cho tính năng nào — để bất kỳ developer nào cũng có thể hiểu, sử dụng và mở rộng một cách tự tin.

## Mục lục

1. [Bức tranh tổng thể](#1-bức-tranh-tổng-thể)
2. [Hành trình của một lần gọi log](#2-hành-trình-của-một-lần-gọi-log)
3. [Chi tiết từng thành phần](#3-chi-tiết-từng-thành-phần)
4. [Mô hình threading](#4-mô-hình-threading)
5. [Nên dùng level nào?](#5-nên-dùng-level-nào)
6. [Bảng map Tính năng → Thành phần](#6-bảng-map-tính-năng--thành-phần)
7. [Mở rộng Logger](#7-mở-rộng-logger)

---

## 1. Bức tranh tổng thể

Package được xây dựng quanh một ý tưởng duy nhất: **mỗi lần gọi log tạo ra một event, và event đó chảy qua một pipeline gồm các tầng nhỏ có thể thay thế**.

```
 Code của bạn                  Pipeline                           Đầu ra
┌──────────┐   ┌──────────────────────────────────────────┐   ┌──────────────┐
│ logger   │ → │ Check level → Filter → Sample → Redact → │ → │ Console      │
│ .info()  │   │ Format → Emit                            │   │ File         │
└──────────┘   └──────────────────────────────────────────┘   │ os_log       │
                                                              │ Remote SDK   │
                                                              └──────────────┘
```

Mỗi tầng là một protocol (`LogFilter`, `LogRedactor`, `LogFormatter`, `LogSink`), và các implementation có sẵn chỉ là mặc định. Bạn có thể thay hoặc thêm bất kỳ tầng nào mà không đụng đến các tầng còn lại.

Hai nguyên tắc thiết kế xuyên suốt:

- **Thread của người gọi làm ít việc nhất có thể.** Việc nặng (filter, format, I/O) chạy trên background queue.
- **Mọi dữ liệu đi qua ranh giới thread đều `Sendable`.** Toàn bộ package compile và chạy sạch dưới strict concurrency của Swift 6.

## 2. Hành trình của một lần gọi log

Chính xác thì điều gì xảy ra khi bạn viết dòng này?

```swift
logger.info("Order created", tags: ["BUSINESS"], context: ["orderId": "A123"])
```

```
            CALLER THREAD (code của bạn — làm ít việc nhất có thể)
┌ Bước 1. Check level nhanh ──────────────────────────────────────────┐
│ .info >= config.minLevel?  Nếu không → return ngay lập tức.         │
│ Nhờ @autoclosure, chuỗi message và dictionary context               │
│ CHƯA HỀ ĐƯỢC TẠO RA. Một log bị tắt chỉ tốn ~một lần đọc lock.      │
└──────────────────────────────┬──────────────────────────────────────┘
┌ Bước 2. Dựng event ──────────▼──────────────────────────────────────┐
│ • Evaluate message và context (giờ mới biết chắc log sẽ được dùng)  │
│ • Merge context/tags kế thừa từ withContext()/withTags()           │
│ • Convert giá trị context sang LogValue (type-safe, Sendable)       │
│ • Lấy timestamp, thread ("main"/"background"), file:line TẠI ĐÂY — │
│   ngay chỗ gọi log, nên chúng mô tả CODE CỦA BẠN, không phải logger │
└──────────────────────────────┬──────────────────────────────────────┘
┌ Bước 3. Check backpressure ──▼──────────────────────────────────────┐
│ Đã đủ maxQueuedEvents đang chờ? → drop event này, cộng vào bộ đếm.  │
│ (Số event bị drop sẽ được báo sau bằng một warn log tự sinh.)       │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼  chuyển queue — caller thread được giải phóng
            BACKGROUND QUEUE ("logger.core.queue", serial)
┌ Bước 4. Filters ────────────────────────────────────────────────────┐
│ Mọi LogFilter phải đồng ý: MinLevelFilter, TagFilter, custom...     │
└──────────────────────────────┬──────────────────────────────────────┘
┌ Bước 5. Sampling ────────────▼──────────────────────────────────────┐
│ Chỉ debug/info: giữ lại một phần ngẫu nhiên (samplingRate).         │
│ warn/error/fatal không bao giờ bị sample.                           │
└──────────────────────────────┬──────────────────────────────────────┘
┌ Bước 6. Redaction ───────────▼──────────────────────────────────────┐
│ Key có trong redactKeys (không phân biệt hoa thường, đệ quy)        │
│ → "[REDACTED]". Chạy TRƯỚC khi format, nên không sink nào           │
│ nhìn thấy giá trị gốc.                                              │
└──────────────────────────────┬──────────────────────────────────────┘
┌ Bước 7. Theo từng destination ▼─────────────────────────────────────┐
│ for each LogDestination(formatter, sink, minLevel):                 │
│     event.level >= destination.minLevel?                            │
│         → formatter.format(event)  → sink.emit(formatted, event)    │
└───────┬─────────────────┬─────────────────┬─────────────────────────┘
        ▼                 ▼                 ▼
    Console            File (queue        Remote SDK
    (debug+)           riêng, info+)      (chỉ error+)
```

**Hai trường hợp đặc biệt:**

- **`fatal`** không đi qua queue bất đồng bộ: toàn bộ pipeline chạy **đồng bộ** và mọi sink được flush trước khi return — nên event không bị mất kể cả khi app crash ở đúng dòng kế tiếp.
- **`flush()`** chờ background queue xử lý hết event đang chờ, rồi yêu cầu mọi sink flush buffer riêng của nó (ví dụ file sink). Gọi khi app vào background.

## 3. Chi tiết từng thành phần

### `Logger` — API công khai (struct)

Đây là thành phần mà code của bạn gọi trực tiếp. Nó giữ ba thứ:

| Field | Vai trò |
|---|---|
| `core` | engine dùng chung (xem `LoggerCore`) |
| `baseContext` | context kế thừa từ `withContext(...)` |
| `baseTags` | tags kế thừa từ `withTags(...)` |

`Logger` là một struct rất nhỏ — copy gần như miễn phí, và `withContext`/`withTags` chỉ trả về một bản copy kèm thêm context/tags. **Mọi bản copy dùng chung một `LoggerCore`**, tức là chung một queue, một config, một bộ destinations:

```swift
let base = Logger(...)                       // 1 core, 1 queue
let net  = base.withTags(["NETWORK"])        // cùng core
let user = net.withContext(["userId": "u1"]) // cùng core
```

Đây là lý do setup khuyến nghị là một `Logger` dùng chung + các child phái sinh từ nó, thay vì tạo nhiều instance `Logger(...)` độc lập.

Nó cũng cung cấp `updateConfiguration { ... }` (đổi config lúc runtime, thread-safe) và `flush()`.

### `LoggerCore` — engine (internal)

Bạn không gọi trực tiếp thành phần này. Nó quản lý:

- **configuration** đặt sau một `NSLock` (để fast path đọc được `minLevel` đồng bộ từ bất kỳ thread nào),
- **serial background queue** nơi pipeline chạy,
- **bộ đếm backpressure** (số event đang chờ + số event đã drop),
- và bản thân pipeline: filters → sampling → redaction → destinations.

### `LogEvent` — đơn vị dữ liệu

Một lần gọi log = một `LogEvent` immutable:

| Field | Là gì | Vì sao tồn tại |
|---|---|---|
| `id: UUID` | duy nhất cho mỗi event | dedup khi remote gửi lại (retry) |
| `timestamp: Date` | thời điểm bạn gọi logger | lấy tại chỗ gọi, không phải lúc queue xử lý |
| `level: LogLevel` | mức nghiêm trọng | filter và định tuyến |
| `message: String` | tóm tắt cho người đọc | "tiêu đề" của event |
| `tags: [String]` | nhãn subsystem (`"UI"`, `"NETWORK"`) | filter, child logger |
| `context: [String: LogValue]` | dữ liệu có cấu trúc | các field query được trên collector |
| `thread: String?` | `"main"` / `"background"` | debug vấn đề threading |
| `source: SourceInfo?` | file, function, line | nhảy thẳng đến chỗ gọi log |

### `LogLevel` — mức nghiêm trọng (enum, `Comparable`)

`debug < info < warn < error < fatal`. Nhờ `Comparable` mà mọi phép check `minLevel` chỉ là một phép so sánh. Xem [mục 5](#5-nên-dùng-level-nào) để biết khi nào dùng level nào.

### `LogValue` — giá trị context type-safe

Vì sao `LogEvent` không mang thẳng `[String: Any]`? Hai lý do:

1. `Any` không `Sendable` — không thể đi qua background queue một cách hợp lệ trong Swift 6.
2. `Any` không `Encodable` — muốn format JSON sẽ phải cast lúc runtime, rất dễ vỡ.

Nên API công khai vẫn nhận `[String: Any]` cho tiện, và `LogValue.from(_:)` convert **một lần, ngay tại chỗ gọi** thành một tập case cố định: `.string`, `.int`, `.double`, `.bool`, `.object`, `.array`, `.null`. Quy tắc convert:

- Mọi kiểu số nguyên → `.int`; `Float` → `.double`; `Date` → `.string` ISO-8601; `URL` → `.string`.
- Dictionary/array lồng nhau được convert đệ quy.
- Kiểu không hỗ trợ sẽ fallback về `String(describing:)` — không bao giờ crash, nhưng custom type sẽ thành chuỗi thô (hãy cân nhắc trước khi đưa gì vào context).

### `LoggerConfiguration` — toàn bộ tùy chọn cấu hình (struct, `Sendable`)

| Field | Mặc định | Điều khiển |
|---|---|---|
| `minLevel` | `.info` | mức tối thiểu chung; log dưới mức này gần như không tốn chi phí |
| `enabledTags` | `nil` (tất cả) | danh sách tag cho phép, dùng bởi `TagFilter` |
| `redactKeys` | password, token, authorization, cookie, email, phone | key nào trong context bị che |
| `samplingRate` | `1.0` | tỉ lệ debug/info được giữ lại |
| `includeSourceInfo` | `true` | đính kèm file/function/line |
| `includeThread` | `true` | đính kèm `"main"`/`"background"` |
| `maxQueuedEvents` | `1000` | giới hạn backpressure |
| `dateFormatStyle` | ISO-8601, time zone hiện tại | cách hiển thị timestamp |
| `dateProvider` | `Date.init` | nguồn thời gian inject được — cố định trong test để output ổn định |

Đổi được lúc runtime qua `logger.updateConfiguration { ... }` (ví dụ một debug menu bật `minLevel` về `.debug`).

### `LogFilter` — bộ lọc (protocol)

```swift
public protocol LogFilter: Sendable {
    func shouldLog(event: LogEvent, config: LoggerConfiguration) -> Bool
}
```

Mọi filter phải chấp thuận thì event mới đi tiếp, ngược lại event bị drop. Có sẵn:

- **`MinLevelFilter`** — `event.level >= config.minLevel`.
- **`TagFilter`** — nếu `enabledTags` được đặt, event phải mang ít nhất một tag trong đó. **Event không có tag luôn được cho qua**, nên log chung không bao giờ bị tắt nhầm.

### `LogRedactor` — tầng bảo vệ privacy (protocol)

```swift
public protocol LogRedactor: Sendable {
    func redact(context: [String: LogValue], keys: Set<String>) -> [String: LogValue]
}
```

**`DefaultRedactor`** che mọi key có trong `redactKeys` — không phân biệt hoa thường, áp dụng đệ quy vào object và array lồng nhau. Nó chạy **trước** khi format, nên không formatter hay sink nào nhìn thấy giá trị gốc.

> Giới hạn cần nhớ: chỉ so khớp **key**. Không bao giờ quét giá trị hay chuỗi message. `logger.info("User \(email) ...")` sẽ làm lộ email.

### `LogFormatter` — biến event thành text (protocol)

```swift
public protocol LogFormatter: Sendable {
    func format(event: LogEvent, config: LoggerConfiguration) -> String
}
```

- **`PrettyLogFormatter`** — một dòng dễ đọc cho con người:
  `2026-06-07T10:00:00Z [ERROR][BUSINESS]{main} Payment failed {"orderId":"A123"} (Checkout.swift:42 pay())`
- **`JSONLogFormatter`** — mỗi dòng một JSON object (key được sort, format ổn định) cho file và log collector. Nếu encode lỗi, nó trả về một JSON báo lỗi tối giản thay vì throw.

### `LogSink` — đưa text đến đích (protocol)

```swift
public protocol LogSink: Sendable {
    func emit(_ formatted: String, event: LogEvent)
    func flush()   // mặc định: không làm gì
}
```

`emit` nhận cả chuỗi đã format **lẫn** event gốc — các adapter (analytics, crash reporter) thường cần field có cấu trúc chứ không phải chuỗi. Có sẵn:

| Sink | Đích | Ghi chú |
|---|---|---|
| `ConsoleLogSink` | `print` | chỉ dùng cho development |
| `OSLogSink` | unified logging | hiện trong Console.app & sysdiagnose; map `fatal` → `.fault`; dòng log là `privacy: .public` (redaction đã chạy trước) |
| `FileLogSink` | file | có queue serial riêng; giữ file handle mở; rotate theo dung lượng (`app.log` → `.1` → `.2`...); tự tạo lại nếu file bị xóa; tự tạo thư mục cha; `flush()` ghi xuống disk |
| `RemoteLogSink` | closure của bạn | điểm tích hợp cho Crashlytics/Sentry/backend riêng |

### `LogDestination` — formatter + sink + level (struct)

```swift
LogDestination(formatter: JSONLogFormatter(), sink: fileSink, minLevel: .info)
```

Vì sao ghép thành bộ? Vì **cùng một event thường cần format khác nhau ở những nơi khác nhau** — text dễ đọc trên console, JSON trong file, JSON lên remote. Và `minLevel` riêng từng destination cho phép một lần gọi log được phân phối có chọn lọc: console nhận `debug+`, file `info+`, remote `error+`.

### `LoggerProtocol` — abstraction cho DI và testing

`Logger` conform `LoggerProtocol` (bản thân protocol cũng là `Sendable`). Inject protocol vào service của bạn, để khi test có thể truyền vào một logger nối với capturing sink. Extension của protocol cung cấp sẵn toàn bộ default argument và overload tiện dụng `error(_:error:)`, nên conformer tự viết cũng được hưởng trọn bộ API.

## 4. Mô hình threading

| Việc | Chạy ở đâu |
|---|---|
| Check level nhanh | caller thread (một lần đọc lock) |
| Evaluate message/context, convert LogValue | caller thread (chỉ khi log vượt qua check level) |
| Lấy timestamp/thread/source | caller thread (để giá trị mô tả đúng chỗ gọi log) |
| Filters, sampling, redaction, formatting | `logger.core.queue` (serial, QoS `.utility`) |
| Emit của Console/OSLog/Remote | `logger.core.queue` |
| Ghi file | queue serial riêng của `FileLogSink` |
| Pipeline của `fatal` | caller thread, chạy đồng bộ (để an toàn khi crash) |
| `flush()` | caller thread, chờ đồng bộ cả hai queue xử lý xong |

Những bảo đảm có được từ thiết kế này:

- **Đúng thứ tự** — core queue là serial, event được xử lý theo đúng thứ tự enqueue.
- **Không data race** — config được đọc/ghi sau lock; mọi type đi qua ranh giới queue đều `Sendable`; điều này được **compiler Swift 6 kiểm tra và đảm bảo**, không phải quy ước tự giác.
- **Memory có giới hạn** — tối đa `maxQueuedEvents` event chờ trong queue; vượt ngưỡng thì event bị drop và việc drop luôn được *báo lại* (warn log tự sinh), không bao giờ âm thầm.

## 5. Nên dùng level nào?

| Level | Dùng cho | Ví dụ | Hành vi ở production |
|---|---|---|---|
| `debug` | chi tiết kỹ thuật chỉ dev cần | cache hit, parse JSON xong, view lifecycle | thường bị lọc hoặc sample mạnh |
| `info` | sự kiện nghiệp vụ bình thường | đăng nhập, tạo đơn hàng, mở màn hình | giữ ở local, sample nếu quá nhiều |
| `warn` | có gì đó bất thường, nhưng app đã tự xử lý được | request phải retry, response chậm, phải dùng fallback | luôn giữ; theo dõi xu hướng |
| `error` | một thao tác thất bại; người dùng bị ảnh hưởng | thanh toán lỗi, API trả 500, ghi file thất bại | luôn giữ; thường ship lên remote |
| `fatal` | app không thể tiếp tục chạy | không mở được database, thiếu config bắt buộc | xử lý đồng bộ + flush; đi kèm `fatalError()` |

Quy tắc nhanh: *nếu bạn muốn thấy nó khi điều tra một khiếu nại của người dùng → `info` trở lên. Nếu nó đáng để gọi ai đó dậy lúc nửa đêm → `error` trở lên.*

## 6. Bảng map Tính năng → Thành phần

| Tính năng | Được thực hiện bởi |
|---|---|
| Gần như zero-cost cho level bị tắt | `@autoclosure` trong `Logger`/`LoggerProtocol` + `minLevel` đọc qua lock trong `LoggerCore` |
| Kế thừa context/tags | `Logger.withContext` / `Logger.withTags` (các bản copy dùng chung một core) |
| Log lỗi có cấu trúc | `error(_:error:)` trong extension của `LoggerProtocol` |
| Lọc theo level/tag | `MinLevelFilter`, `TagFilter` |
| Level riêng từng destination | `LogDestination.minLevel` |
| Che dữ liệu nhạy cảm | `DefaultRedactor` + `redactKeys` |
| Kiểm soát noise/chi phí | sampling trong `LoggerCore` (`samplingRate`) |
| Chống log storm | bộ đếm backpressure trong `LoggerCore` (`maxQueuedEvents`) |
| Fatal log không mất khi crash | nhánh xử lý đồng bộ trong `LoggerCore.enqueue` |
| Chủ động flush log | `Logger.flush()` → core queue + `LogSink.flush()` |
| File rotation & tự phục hồi | `FileLogSink` |
| Console.app / sysdiagnose | `OSLogSink` |
| Tích hợp SDK bên thứ ba | `RemoteLogSink` (pattern facade) |
| Swift 6 / an toàn với actor | mọi public type đều `Sendable` |
| Dễ test | `LoggerProtocol` + `dateProvider` inject được + `flush()` |

## 7. Mở rộng Logger

Mỗi tầng pipeline là một protocol nhỏ — implement rồi truyền vào:

| Bạn muốn... | Implement | Truyền vào qua |
|---|---|---|
| Gửi log đến một đích mới | `LogSink` | `LogDestination(formatter:sink:minLevel:)` |
| Đổi format output | `LogFormatter` | `LogDestination(formatter:...)` |
| Drop event theo quy tắc riêng | `LogFilter` | `Logger(filters: [...])` |
| Che dữ liệu theo cách riêng | `LogRedactor` | `Logger(redactors: [...])` |

Yêu cầu đối với component tự viết: phải `Sendable` (compiler sẽ kiểm tra), `emit` không được throw hay block lâu (nó chạy trên queue pipeline dùng chung — hãy tự tạo queue riêng cho I/O chậm, như cách `FileLogSink` đã làm), và `flush()` phải xử lý xong đồng bộ mọi dữ liệu còn trong buffer.

---

Xem công thức copy-paste cho từng use case tại [README](README.vi.md).
